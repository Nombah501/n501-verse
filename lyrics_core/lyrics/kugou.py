"""Kugou (酷狗) synchronized-lyrics provider.

Kugou's lyric endpoints are open and return plain timed LRC (with ``fmt=lrc`` the
content is base64 LRC, not the encrypted KRC), so no key handling is needed. The
search matches on the song title alone — passing "artist title" returns nothing —
so we query the cleaned title(s) and let the shared matcher rank the candidates by
artist and duration.
"""

from __future__ import annotations

import asyncio
import base64
import binascii
import logging
from collections.abc import Mapping
from dataclasses import dataclass


from .artifact import LyricsArtifact
from .http import LyricsHttpError, LyricsSession, LyricsTimeout
from .krc_parser import parse_krc
from .lrc_parser import parse_lrc
from .match import Candidate, MatchConfidence, TrackMetadata, evaluate_match, query_variants, ranked_matches
from .models import LyricLine
from .payload import read_json_capped
from .search_policy import MANUAL_SEARCH_RESULTS_PER_PROVIDER
from .title_grammar import base_title

logger = logging.getLogger(__name__)

SEARCH_URL = "https://lyrics.kugou.com/search"
DOWNLOAD_URL = "https://lyrics.kugou.com/download"
HEADERS = {"User-Agent": "Mozilla/5.0", "Referer": "https://www.kugou.com/"}
TIMEOUT = LyricsTimeout(8.0)
# A title search returns many same-title covers; cap how many we actually download
# lyrics for so a common title can't fan out into a pile of requests.
_MAX_FETCHES = 5
_MANUAL_SEARCH_CONCURRENCY = 8


@dataclass(frozen=True)
class Record:
    cand_id: str
    accesskey: str
    title: str
    artist: str
    duration_s: float | None


def _records(data: object) -> list[Record]:
    if not isinstance(data, dict):
        raise ValueError("Kugou search response is not an object")
    candidates = data.get("candidates")
    if not isinstance(candidates, list):
        return []
    records: list[Record] = []
    for item in candidates:
        if not isinstance(item, dict):
            continue
        cand_id = item.get("id")
        accesskey = item.get("accesskey")
        if cand_id is None or not accesskey:
            continue
        duration = item.get("duration")  # milliseconds
        records.append(
            Record(
                cand_id=str(cand_id),
                accesskey=str(accesskey),
                title=str(item.get("song", "")),
                artist=str(item.get("singer", "")),
                duration_s=duration / 1000.0 if isinstance(duration, (int, float)) else None,
            )
        )
    return records


async def search(session: LyricsSession, keyword: str) -> list[Record]:
    params = {"ver": "1", "man": "yes", "client": "pc", "keyword": keyword}
    async with session.get(SEARCH_URL, params=params, headers=HEADERS, timeout=TIMEOUT) as response:
        response.raise_for_status()
        data = await read_json_capped(response, "Kugou")
    return _records(data)


async def _download_content(session: LyricsSession, record: Record, fmt: str) -> bytes:
    params = {
        "ver": "1",
        "client": "pc",
        "fmt": fmt,
        "charset": "utf8",
        "id": record.cand_id,
        "accesskey": record.accesskey,
    }
    async with session.get(DOWNLOAD_URL, params=params, headers=HEADERS, timeout=TIMEOUT) as response:
        response.raise_for_status()
        data = await read_json_capped(response, "Kugou")
    if not isinstance(data, dict):
        raise ValueError("Kugou download response is not an object")
    content = data.get("content")
    if not isinstance(content, str) or not content:
        return b""
    try:
        return base64.b64decode(content, validate=True)
    except (binascii.Error, ValueError):
        return b""


async def download_lrc(session: LyricsSession, record: Record) -> str:
    body = await _download_content(session, record, "lrc")
    return body.decode("utf-8", "replace")


async def download_krc(session: LyricsSession, record: Record) -> bytes:
    return await _download_content(session, record, "krc")


def parse_payload(payload: Mapping[str, str]) -> tuple[LyricLine, ...]:
    """Parse either payload shape this provider stores.

    A word-timed hit is cached as base64 KRC and a plain one as LRC. Reading only
    the LRC key made every cached KRC row fail to parse, and the cache deletes a
    row it cannot parse — so the word-timed path refetched on every lookup.
    """
    krc = payload.get("krc", "")
    if krc:
        try:
            return tuple(parse_krc(base64.b64decode(krc)))
        except (ValueError, binascii.Error):
            return ()
    return tuple(parse_lrc(payload.get("lrc", "")))


async def search_artifacts(
    session: LyricsSession,
    track: TrackMetadata,
) -> tuple[LyricsArtifact, ...]:
    """Return several selectable Kugou lyric artifacts for manual search."""
    keyword = base_title(track.title).strip() or track.artist.strip()
    records = (await search(session, keyword))[:MANUAL_SEARCH_RESULTS_PER_PROVIDER]
    download_gate = asyncio.Semaphore(_MANUAL_SEARCH_CONCURRENCY)

    async def fetch(record: Record) -> LyricsArtifact | None:
        candidate = Candidate(record.cand_id, record.title, record.artist, record.duration_s)
        evidence = evaluate_match(candidate, track)
        try:
            async with download_gate:
                return await _artifact_for_record(session, record, evidence.confidence)
        except (LyricsHttpError, ValueError) as exc:
            logger.debug("Kugou manual candidate %s failed: %s", record.cand_id, exc)
            return None

    artifacts = await asyncio.gather(*(fetch(record) for record in records))
    return tuple(artifact for artifact in artifacts if artifact is not None)


def _query_keywords(track: TrackMetadata, fuzzy: bool) -> tuple[str, ...]:
    """The search strings for one track, from the shared ladder.

    Kugou takes a single string per request, so each reading is fused. Measured over
    twelve tracks, title alone found 3 and title with performer found 4, while
    sending both found 6; the ladder yields both, and now also the simplified folds
    this provider used to go without."""
    return tuple(
        dict.fromkeys(
            variant.text for variant in query_variants(track, fuzzy=fuzzy) if len(variant.text) >= 2
        )
    )


async def fetch_artifact(
    session: LyricsSession,
    track: TrackMetadata,
    *,
    fuzzy: bool = False,
) -> LyricsArtifact | None:
    by_candidate: dict[str, Record] = {}
    ranked: list[tuple[MatchConfidence, Record]] = []
    seen_ids: set[str] = set()
    for keyword in _query_keywords(track, fuzzy):
        records = await search(session, keyword)
        # Kugou's lyric-search "singer" field is unreliable (often the song name or a
        # nickname), so it is dropped for matching — the title and duration carry the
        # identity here, which is why the track's own duration matters for Kugou.
        candidates = [
            Candidate(record.cand_id, record.title, "", record.duration_s)
            for record in records
        ]
        by_candidate.update(zip((c.song_id for c in candidates), records, strict=True))
        for match in ranked_matches(candidates, track, fuzzy=fuzzy):
            song_id = match.candidate.song_id
            if song_id in seen_ids:
                continue
            seen_ids.add(song_id)
            ranked.append((match.confidence, by_candidate[song_id]))

    # HIGH picks first, then the rest, capped, until one download yields real lines.
    ranked.sort(key=lambda item: item[0] is MatchConfidence.HIGH, reverse=True)
    for attempt, (confidence, record) in enumerate(ranked):
        if attempt >= _MAX_FETCHES:
            break
        try:
            artifact = await _artifact_for_record(session, record, confidence)
        except (LyricsHttpError, ValueError):
            continue
        if artifact is not None:
            return artifact
    return None


async def _artifact_for_record(
    session: LyricsSession,
    record: Record,
    confidence: MatchConfidence,
) -> LyricsArtifact | None:
    """Download and parse one Kugou record for automatic or manual selection."""
    # Fetching and parsing are separated because they fail differently: a candidate
    # that cannot be fetched has nothing left to try, while an unusable KRC can still
    # have a plain LRC representation at the same endpoint.
    krc = await download_krc(session, record)
    try:
        lines = tuple(parse_krc(krc))
    except ValueError:
        lines = ()
    if lines:
        payload = {"krc": base64.b64encode(krc).decode("ascii")}
    else:
        plain_lrc = krc.decode("utf-8", "replace")
        lines = parse_payload({"lrc": plain_lrc})
        if lines:
            payload = {"lrc": plain_lrc}
        elif not krc:
            return None
        else:
            lrc = await download_lrc(session, record)
            lines = parse_payload({"lrc": lrc})
            payload = {"lrc": lrc}
    if not lines:
        return None
    return LyricsArtifact(
        provider="kugou",
        provider_song_id=record.cand_id,
        title=record.title,
        artist=record.artist,
        album="",
        duration_s=record.duration_s,
        payload=payload,
        lines=lines,
        confidence=confidence,
    )
