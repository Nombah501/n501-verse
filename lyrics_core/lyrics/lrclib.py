"""LRCLIB synchronized-lyrics provider."""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Mapping
from dataclasses import dataclass


from ..async_task import create_owned_task
from .artifact import LyricsArtifact
from .artist_grammar import primary_artist
from .http import LyricsHttpError, LyricsSession, LyricsTimeout
from .lrc_parser import MAX_LINES, parse_lrc
from .match import Candidate, MatchEvidence, TrackMetadata, best_match, evaluate_match, query_variants
from .models import LyricLine, TimingKind
from .payload import read_json_capped
from .search_policy import MANUAL_SEARCH_RESULTS_PER_PROVIDER
from .title_grammar import base_title

logger = logging.getLogger(__name__)

GET_URL = "https://lrclib.net/api/get"
SEARCH_URL = "https://lrclib.net/api/search"
HEADERS = {"User-Agent": "n501.karaoke/0.4.0 (https://github.com/Nombah501/n501-verse)"}
# lrclib's backend is routinely slow (measured 7-12s round trips, occasional
# 502s), so it needs a much longer budget than netease or it times out on every
# request and the whole source looks dead. This runs off the UI thread, so
# waiting is fine; the session-wide safety net (20s) still bounds a true hang.
TIMEOUT = LyricsTimeout(15.0)
@dataclass(frozen=True)
class Record:
    song_id: str
    title: str
    artist: str
    album: str
    duration_s: float | None
    synced_lyrics: str
    plain_lyrics: str = ""
    instrumental: bool = False


def _record(data: object) -> Record | None:
    if not isinstance(data, dict):
        return None
    song_id = data.get("id")
    if song_id is None:
        return None
    synced = data.get("syncedLyrics")
    plain = data.get("plainLyrics")
    synced = synced if isinstance(synced, str) else ""
    plain = plain if isinstance(plain, str) else ""
    instrumental = data.get("instrumental") is True
    if not synced.strip() and not plain.strip() and not instrumental:
        return None
    duration = data.get("duration")
    return Record(
        song_id=str(song_id),
        title=str(data.get("trackName", "")),
        artist=str(data.get("artistName", "")),
        album=str(data.get("albumName", "")),
        duration_s=float(duration) if isinstance(duration, (int, float)) else None,
        synced_lyrics=synced,
        plain_lyrics=plain,
        instrumental=instrumental,
    )


async def get_exact(session: LyricsSession, track: TrackMetadata) -> Record | None:
    params = {"track_name": track.title, "artist_name": track.artist}
    if track.duration_s is not None:
        params["duration"] = str(int(round(track.duration_s)))
    async with session.get(GET_URL, params=params, headers=HEADERS, timeout=TIMEOUT) as response:
        if response.status == 404:
            return None
        response.raise_for_status()
        data = await read_json_capped(response, "LRCLIB")
    if not isinstance(data, dict):
        raise ValueError("LRCLIB exact response is not an object")
    return _record(data)


async def _search(session: LyricsSession, track_name: str, artist_name: str) -> list[Record]:
    params = {"track_name": track_name}
    if artist_name:
        params["artist_name"] = artist_name
    async with session.get(SEARCH_URL, params=params, headers=HEADERS, timeout=TIMEOUT) as response:
        response.raise_for_status()
        data = await read_json_capped(response, "LRCLIB")
    if not isinstance(data, list):
        raise ValueError("LRCLIB search response is not a list")
    return [record for item in data if (record := _record(item)) is not None]


async def search_records(session: LyricsSession, track: TrackMetadata) -> list[Record]:
    return await _search(session, base_title(track.title), primary_artist(track.artist))


def parse_payload(payload: Mapping[str, str]) -> tuple[LyricLine, ...]:
    synced = tuple(parse_lrc(payload.get("syncedLyrics", "")))
    if synced:
        return synced
    plain = payload.get("plainLyrics", "")
    if not isinstance(plain, str):
        return ()
    return tuple(LyricLine(index, f"plain-{index}", 0.0, 0.0, text.strip(), "")
                 for index, text in enumerate(line for line in plain.splitlines() if line.strip())
                 if index < MAX_LINES)


async def search_artifacts(
    session: LyricsSession,
    track: TrackMetadata,
    *,
    song_id: str | None = None,
) -> tuple[LyricsArtifact, ...]:
    """Return selectable LRCLIB artifacts, or a saved song from all search rows."""
    records = await search_records(session, track)
    records = ([record for record in records if record.song_id == song_id]
               if song_id is not None else records[:MANUAL_SEARCH_RESULTS_PER_PROVIDER])
    artifacts: list[LyricsArtifact] = []
    for record in records:
        candidate = Candidate(record.song_id, record.title, record.artist, record.duration_s, album=record.album)
        artifact = _artifact_from_record(record, evaluate_match(candidate, track))
        if artifact is not None:
            artifacts.append(artifact)
    return tuple(artifacts)


async def fetch_artifact(
    session: LyricsSession,
    track: TrackMetadata,
    *,
    fuzzy: bool = False,
) -> LyricsArtifact | None:
    async def exact_records() -> list[Record]:
        exact = await get_exact(session, track)
        return [exact] if exact is not None else []

    pending: dict[asyncio.Task[list[Record]], str] = {}
    records: list[Record] = []
    errors: list[Exception] = []
    successful_requests = 0
    try:
        pending[create_owned_task(exact_records(), name="kotonoha-lrclib-exact")] = "exact"
        pending[create_owned_task(search_records(session, track), name="kotonoha-lrclib-search")] = "search"
        if fuzzy:
            # Salvage noisy browser titles: search each cleaned CJK/Latin run on its own
            # (no artist, since a YouTube "artist" is usually the channel), so a
            # bracket-and-channel-laden title still finds the track.
            # Only the salvaged rungs: the exact and search stages above already sent the
            # reported metadata, and the ladder's other readings are built from it. The
            # simplified folds are new here — this provider used to assemble its own
            # ladder and go without them.
            for variant in query_variants(track, fuzzy=True):
                if not variant.rung.startswith("salvaged"):
                    continue
                pending[create_owned_task(
                    _search(session, variant.title, variant.artist),
                    name="kotonoha-lrclib-fuzzy",
                )] = "fuzzy"
        while pending:
            done, _remaining = await asyncio.wait(pending, return_when=asyncio.FIRST_COMPLETED)
            for task in done:
                stage = pending.pop(task)
                try:
                    records.extend(task.result())
                    successful_requests += 1
                except (TimeoutError, LyricsHttpError, ValueError) as exc:
                    errors.append(exc)
                    logger.debug("LRCLIB %s lookup failed: %s: %s", stage, type(exc).__name__, exc)

            artifact = _artifact_from_records(records, track, fuzzy=fuzzy)
            if (artifact is not None and artifact.confidence.value == "high"
                    and artifact.timing not in (TimingKind.UNSYNCED, TimingKind.INSTRUMENTAL)):
                return artifact

        artifact = _artifact_from_records(records, track, fuzzy=fuzzy)
        if artifact is not None:
            return artifact
        if successful_requests == 0 and errors:
            raise errors[0]
        return None
    finally:
        remaining = tuple(pending)
        for task in remaining:
            task.cancel()
        if remaining:
            await asyncio.gather(*remaining, return_exceptions=True)


def _artifact_from_records(
    records: list[Record], track: TrackMetadata, *, fuzzy: bool = False
) -> LyricsArtifact | None:
    # Resolve the best timed match first; an unrelated timed result must not
    # suppress a matching Unsynced record from the same provider.
    timed = [record for record in records if parse_lrc(record.synced_lyrics)]
    lyrics = [record for record in records if record not in timed and record.plain_lyrics.strip()]
    for group in (timed, lyrics, [record for record in records if record.instrumental]):
        candidates = [
            Candidate(record.song_id, record.title, record.artist, record.duration_s, album=record.album)
            for record in group
        ]
        match = best_match(candidates, track, fuzzy=fuzzy)
        if match is None:
            continue
        record = next(
            item for item in group
            if Candidate(item.song_id, item.title, item.artist, item.duration_s, album=item.album) == match.candidate
        )
        artifact = _artifact_from_record(record, match)
        if artifact is not None:
            return artifact
    return None


def _artifact_from_record(record: Record, evidence: MatchEvidence) -> LyricsArtifact | None:
    """Build one validated artifact while retaining the search result metadata."""
    payload = {"syncedLyrics": record.synced_lyrics, "plainLyrics": record.plain_lyrics}
    if record.instrumental and not record.synced_lyrics.strip() and not record.plain_lyrics.strip():
        payload["instrumental"] = "true"
    lines = parse_payload(payload)
    if not lines and not record.instrumental:
        return None
    return LyricsArtifact(
        provider="lrclib",
        provider_song_id=record.song_id,
        title=record.title,
        artist=record.artist,
        album=record.album,
        duration_s=record.duration_s,
        payload=payload,
        lines=lines,
        confidence=evidence.confidence,
        timing=(TimingKind.LINE if parse_lrc(record.synced_lyrics) else
                TimingKind.UNSYNCED if lines else TimingKind.INSTRUMENTAL),
    )
