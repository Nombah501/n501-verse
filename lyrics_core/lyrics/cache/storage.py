"""Synchronous SQLite storage for the lyrics cache facade."""

from __future__ import annotations

import json
import os
import sqlite3
import time
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Final

from ..artifact import LyricsArtifact
from ..match import Candidate, MatchConfidence, MatchEvidence, TrackMetadata, evaluate_match
from ..models import LyricLine, TimingKind
from ..title_grammar import NORMALIZER_VERSION
from .models import (
    CacheDeleteResult,
    CacheDeleteStatus,
    CacheWriteResult,
    CacheWriteStatus,
    LyricsCacheEntry,
    LyricsCacheHit,
    LyricsCacheKey,
    LyricsCacheMode,
    LyricsCacheQuery,
)

CACHE_SCHEMA_VERSION = 1
DEFAULT_MAX_ENTRIES = 1000
_CACHE_SEARCH_FIELDS: Final[tuple[str, ...]] = ("title", "artist", "album", "provider", "provider_song_id")

PayloadParser = Callable[[Mapping[str, str]], tuple[LyricLine, ...]]

_SCHEMA = """
CREATE TABLE IF NOT EXISTS lyrics (
    provider TEXT NOT NULL,
    provider_song_id TEXT NOT NULL,
    title TEXT NOT NULL,
    artist TEXT NOT NULL,
    album TEXT NOT NULL,
    mode TEXT NOT NULL DEFAULT 'auto',
    duration_s REAL,
    payload_json TEXT NOT NULL,
    fetched_at REAL NOT NULL,
    last_accessed REAL NOT NULL,
    schema_version INTEGER NOT NULL,
    normalizer_version INTEGER NOT NULL,
    PRIMARY KEY (provider, provider_song_id)
);
CREATE INDEX IF NOT EXISTS lyrics_provider_access
    ON lyrics(provider, last_accessed DESC);
"""


def cache_path() -> Path:
    """Return the XDG cache path used by the application by default."""
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(base) / "n501.karaoke" / "lyrics.sqlite3"


class LyricsCacheStorage:
    """Own synchronous SQLite operations for one validated cache database."""

    def __init__(self, path: Path, *, max_entries: int) -> None:
        """Create a storage owner without opening a database connection."""
        self._path = path
        self._max_entries = max(1, max_entries)

    def lookup(self, provider: str, track: TrackMetadata, parser: PayloadParser) -> LyricsCacheHit | None:
        """Return one high-confidence automatic hit for a provider."""
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM lyrics "
                "WHERE provider = ? AND mode = ? AND schema_version = ? AND normalizer_version = ?",
                (provider, LyricsCacheMode.AUTO.value, CACHE_SCHEMA_VERSION, NORMALIZER_VERSION),
            ).fetchall()
            matches: list[tuple[MatchEvidence, sqlite3.Row]] = []
            for row in rows:
                evidence = self._match_row(row, track)
                if evidence.confidence is MatchConfidence.HIGH:
                    matches.append((evidence, row))
            hits = [
                (hit, evidence) for evidence, row in matches
                if (hit := self._read_hit(connection, row, evidence, parser, LyricsCacheMode.AUTO,
                                          touch=False)) is not None
            ]
            if not hits:
                return None
            selected = max(hits, key=lambda item: (
                0 if item[0].artifact.timing is TimingKind.INSTRUMENTAL else
                1 if item[0].artifact.timing is TimingKind.UNSYNCED else 2,
                self._match_sort_key(item[1]),
            ))[0]
            connection.execute(
                "UPDATE lyrics SET last_accessed = ? WHERE provider = ? AND provider_song_id = ?",
                (time.time(), provider, selected.artifact.provider_song_id),
            )
            return selected

    def lookup_manual(
        self,
        track: TrackMetadata,
        parsers: Mapping[str, PayloadParser],
    ) -> LyricsCacheHit | None:
        """Return the best matching manual selection across known providers."""
        with self._connect() as connection:
            rows = connection.execute(
                "SELECT * FROM lyrics "
                "WHERE mode = ? AND schema_version = ? AND normalizer_version = ? "
                "ORDER BY last_accessed DESC, provider ASC, provider_song_id ASC",
                (LyricsCacheMode.MANUAL.value, CACHE_SCHEMA_VERSION, NORMALIZER_VERSION),
            ).fetchall()
            matches: list[tuple[MatchEvidence, sqlite3.Row, PayloadParser]] = []
            for row in rows:
                parser = parsers.get(row["provider"])
                if parser is None:
                    continue
                evidence = self._match_row(row, track)
                if evidence.confidence is not MatchConfidence.NONE:
                    matches.append((evidence, row, parser))

            matches.sort(key=lambda item: self._manual_sort_key(item[0], item[1]), reverse=True)
            for evidence, row, parser in matches:
                hit = self._read_hit(connection, row, evidence, parser, LyricsCacheMode.MANUAL)
                if hit is not None:
                    return hit
            return None

    def search(self, query: LyricsCacheQuery) -> tuple[LyricsCacheEntry, ...]:
        """Return cache metadata in deterministic recent-use order."""
        keyword = query.keyword.strip().casefold()
        with self._connect() as connection:
            if query.provider is None:
                rows = connection.execute(
                    "SELECT provider, provider_song_id, title, artist, album, mode, duration_s, fetched_at, "
                    "last_accessed FROM lyrics ORDER BY last_accessed DESC, provider ASC, provider_song_id ASC"
                ).fetchall()
            else:
                rows = connection.execute(
                    "SELECT provider, provider_song_id, title, artist, album, mode, duration_s, fetched_at, "
                    "last_accessed FROM lyrics WHERE provider = ? "
                    "ORDER BY last_accessed DESC, provider ASC, provider_song_id ASC",
                    (query.provider,),
                ).fetchall()
        entries = tuple(self._entry_from_row(row) for row in rows)
        if not keyword:
            return entries
        return tuple(entry for entry in entries if _entry_matches(entry, keyword))

    def get(self, key: LyricsCacheKey) -> LyricsCacheEntry | None:
        """Return one cache entry by its provider-scoped key."""
        with self._connect() as connection:
            row = connection.execute(
                "SELECT provider, provider_song_id, title, artist, album, mode, duration_s, fetched_at, last_accessed "
                "FROM lyrics WHERE provider = ? AND provider_song_id = ?",
                (key.provider, key.provider_song_id),
            ).fetchone()
        return None if row is None else self._entry_from_row(row)

    def upsert(self, artifact: LyricsArtifact, mode: LyricsCacheMode) -> CacheWriteResult:
        """Create or replace one validated artifact and prune oldest rows."""
        now = time.time()
        payload_json = json.dumps(artifact.payload, ensure_ascii=False, separators=(",", ":"))
        key = LyricsCacheKey(artifact.provider, artifact.provider_song_id)
        with self._connect() as connection:
            existed = connection.execute(
                "SELECT 1 FROM lyrics WHERE provider = ? AND provider_song_id = ?",
                (key.provider, key.provider_song_id),
            ).fetchone() is not None
            connection.execute(
                "INSERT INTO lyrics ("
                "provider, provider_song_id, title, artist, album, mode, duration_s, payload_json, "
                "fetched_at, last_accessed, schema_version, normalizer_version"
                ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(provider, provider_song_id) DO UPDATE SET "
                "title = excluded.title, artist = excluded.artist, album = excluded.album, mode = excluded.mode, "
                "duration_s = excluded.duration_s, payload_json = excluded.payload_json, "
                "fetched_at = excluded.fetched_at, last_accessed = excluded.last_accessed, "
                "schema_version = excluded.schema_version, normalizer_version = excluded.normalizer_version",
                (
                    artifact.provider,
                    artifact.provider_song_id,
                    artifact.title,
                    artifact.artist,
                    artifact.album,
                    mode.value,
                    artifact.duration_s,
                    payload_json,
                    now,
                    now,
                    CACHE_SCHEMA_VERSION,
                    NORMALIZER_VERSION,
                ),
            )
            connection.execute(
                "DELETE FROM lyrics WHERE rowid IN ("
                "SELECT rowid FROM lyrics ORDER BY last_accessed DESC LIMIT -1 OFFSET ?)",
                (self._max_entries,),
            )
        status = CacheWriteStatus.UPDATED if existed else CacheWriteStatus.CREATED
        return CacheWriteResult(key, status)

    def update(self, key: LyricsCacheKey, artifact: LyricsArtifact, mode: LyricsCacheMode) -> CacheWriteResult:
        """Update one existing artifact and preserve its provider-scoped identity."""
        now = time.time()
        payload_json = json.dumps(artifact.payload, ensure_ascii=False, separators=(",", ":"))
        with self._connect() as connection:
            cursor = connection.execute(
                "UPDATE lyrics SET title = ?, artist = ?, album = ?, mode = ?, duration_s = ?, payload_json = ?, "
                "fetched_at = ?, last_accessed = ?, schema_version = ?, normalizer_version = ? "
                "WHERE provider = ? AND provider_song_id = ?",
                (
                    artifact.title,
                    artifact.artist,
                    artifact.album,
                    mode.value,
                    artifact.duration_s,
                    payload_json,
                    now,
                    now,
                    CACHE_SCHEMA_VERSION,
                    NORMALIZER_VERSION,
                    key.provider,
                    key.provider_song_id,
                ),
            )
        status = CacheWriteStatus.UPDATED if cursor.rowcount else CacheWriteStatus.NOT_FOUND
        return CacheWriteResult(key, status)

    def delete(self, key: LyricsCacheKey) -> CacheDeleteResult:
        """Delete one cache entry and report whether it existed."""
        with self._connect() as connection:
            cursor = connection.execute(
                "DELETE FROM lyrics WHERE provider = ? AND provider_song_id = ?",
                (key.provider, key.provider_song_id),
            )
        status = CacheDeleteStatus.DELETED if cursor.rowcount else CacheDeleteStatus.NOT_FOUND
        return CacheDeleteResult(key, status)

    def delete_many(self, keys: tuple[LyricsCacheKey, ...]) -> tuple[CacheDeleteResult, ...]:
        """Delete several exact entries in one SQLite transaction."""
        with self._connect() as connection:
            results: list[CacheDeleteResult] = []
            for key in keys:
                cursor = connection.execute(
                    "DELETE FROM lyrics WHERE provider = ? AND provider_song_id = ?",
                    (key.provider, key.provider_song_id),
                )
                status = CacheDeleteStatus.DELETED if cursor.rowcount else CacheDeleteStatus.NOT_FOUND
                results.append(CacheDeleteResult(key, status))
        return tuple(results)

    def clear_automatic(self) -> int:
        """Delete automatic entries only; manual (user-selected) entries stay. Returns rows removed."""
        with self._connect() as connection:
            cursor = connection.execute("DELETE FROM lyrics WHERE mode = ?", (LyricsCacheMode.AUTO.value,))
        return cursor.rowcount

    def count(self, mode: LyricsCacheMode | None = None) -> int:
        """Return the number of persisted entries, optionally of one mode."""
        with self._connect() as connection:
            if mode is None:
                row = connection.execute("SELECT COUNT(*) AS count FROM lyrics").fetchone()
            else:
                row = connection.execute(
                    "SELECT COUNT(*) AS count FROM lyrics WHERE mode = ?", (mode.value,)).fetchone()
        return int(row["count"]) if row is not None else 0

    def _connect(self) -> sqlite3.Connection:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        connection = sqlite3.connect(self._path, timeout=3.0)
        connection.row_factory = sqlite3.Row
        connection.executescript(_SCHEMA)
        self._ensure_mode_column(connection)
        return connection

    @staticmethod
    def _ensure_mode_column(connection: sqlite3.Connection) -> None:
        """Add metadata introduced after the first cache schema without losing rows."""
        columns = {row["name"] for row in connection.execute("PRAGMA table_info(lyrics)")}
        if "mode" not in columns:
            connection.execute("ALTER TABLE lyrics ADD COLUMN mode TEXT NOT NULL DEFAULT 'auto'")

    @staticmethod
    def _match_row(row: sqlite3.Row, track: TrackMetadata) -> MatchEvidence:
        """Build match evidence from one validated cache metadata row."""
        candidate = Candidate(
            song_id=row["provider_song_id"],
            title=row["title"],
            artist=row["artist"],
            duration_s=row["duration_s"],
            album=row["album"],
        )
        return evaluate_match(candidate, track)

    def _read_hit(
        self,
        connection: sqlite3.Connection,
        row: sqlite3.Row,
        evidence: MatchEvidence,
        parser: PayloadParser,
        mode: LyricsCacheMode,
        *, touch: bool = True,
    ) -> LyricsCacheHit | None:
        """Parse one selected row and remove it when its payload is invalid."""
        provider = row["provider"]
        try:
            raw_payload = json.loads(row["payload_json"])
            if not isinstance(raw_payload, dict) or not all(
                isinstance(key, str) and isinstance(value, str) for key, value in raw_payload.items()
            ):
                raise TypeError("cached payload is not a string map")
            payload: dict[str, str] = raw_payload
            instrumental = provider == "lrclib" and payload.get("instrumental") == "true"
            lines = parser(payload)
            if not lines and not instrumental:
                raise ValueError("cached payload has no lyrics")
        except (json.JSONDecodeError, TypeError, ValueError):
            connection.execute(
                "DELETE FROM lyrics WHERE provider = ? AND provider_song_id = ?",
                (provider, row["provider_song_id"]),
            )
            return None

        if touch:
            connection.execute(
                "UPDATE lyrics SET last_accessed = ? WHERE provider = ? AND provider_song_id = ?",
                (time.time(), provider, row["provider_song_id"]),
            )
        return LyricsCacheHit(
            artifact=LyricsArtifact(
                provider=provider,
                provider_song_id=row["provider_song_id"],
                title=row["title"],
                artist=row["artist"],
                album=row["album"],
                duration_s=row["duration_s"],
                payload=payload,
                lines=lines,
                confidence=evidence.confidence,
                timing=(TimingKind.INSTRUMENTAL if instrumental and not lines else
                        TimingKind.UNSYNCED if provider == "lrclib"
                        and not any(line.start != 0 or line.end != 0 or line.words for line in lines)
                        and bool(payload.get("plainLyrics")) else None),
            ),
            mode=mode,
        )

    @staticmethod
    def _match_sort_key(evidence: MatchEvidence) -> tuple[bool, bool, bool, float]:
        duration_rank = -evidence.duration_delta if evidence.duration_delta is not None else float("-inf")
        return evidence.title_exact, evidence.artist_overlap, evidence.album_match, duration_rank

    @staticmethod
    def _manual_sort_key(evidence: MatchEvidence, row: sqlite3.Row) -> tuple[int, bool, bool, bool, float, float]:
        confidence_rank = {
            MatchConfidence.NONE: 0,
            MatchConfidence.MEDIUM: 1,
            MatchConfidence.HIGH: 2,
        }
        duration_rank = -evidence.duration_delta if evidence.duration_delta is not None else float("-inf")
        last_accessed = row["last_accessed"]
        return (
            confidence_rank[evidence.confidence],
            evidence.title_exact,
            evidence.artist_overlap,
            evidence.album_match,
            duration_rank,
            float(last_accessed) if isinstance(last_accessed, (int, float)) else float("-inf"),
        )

    @staticmethod
    def _entry_from_row(row: sqlite3.Row) -> LyricsCacheEntry:
        """Validate one SQLite metadata row before exposing it to the application."""
        provider = row["provider"]
        provider_song_id = row["provider_song_id"]
        title = row["title"]
        artist = row["artist"]
        album = row["album"]
        raw_mode = row["mode"]
        duration = row["duration_s"]
        fetched_at = row["fetched_at"]
        last_accessed = row["last_accessed"]
        if not all(isinstance(value, str) for value in (provider, provider_song_id, title, artist, album, raw_mode)):
            raise TypeError("cache metadata contains a non-string value")
        try:
            mode = LyricsCacheMode(raw_mode)
        except ValueError as exc:
            raise ValueError("cache mode is invalid") from exc
        if duration is not None and (not isinstance(duration, (int, float)) or isinstance(duration, bool)):
            raise TypeError("cache duration is not numeric")
        if not isinstance(fetched_at, (int, float)) or isinstance(fetched_at, bool):
            raise TypeError("cache fetch time is not numeric")
        if not isinstance(last_accessed, (int, float)) or isinstance(last_accessed, bool):
            raise TypeError("cache access time is not numeric")
        return LyricsCacheEntry(
            key=LyricsCacheKey(provider, provider_song_id),
            title=title,
            artist=artist,
            album=album,
            duration_s=float(duration) if duration is not None else None,
            fetched_at=float(fetched_at),
            last_accessed=float(last_accessed),
            mode=mode,
        )


def _entry_matches(entry: LyricsCacheEntry, keyword: str) -> bool:
    """Match a case-folded keyword against all searchable cache metadata."""
    values = {
        "title": entry.title,
        "artist": entry.artist,
        "album": entry.album,
        "provider": entry.key.provider,
        "provider_song_id": entry.key.provider_song_id,
    }
    return any(keyword in values[field].casefold() for field in _CACHE_SEARCH_FIELDS)


__all__ = [
    "CACHE_SCHEMA_VERSION",
    "DEFAULT_MAX_ENTRIES",
    "LyricsCacheStorage",
    "PayloadParser",
    "cache_path",
]
