"""SQLite persistence for structured lyric timing corrections."""

from __future__ import annotations

import os
import sqlite3
from pathlib import Path
from time import time

from ..display.offsets import TrackOffsetEntry, TrackOffsetKey, TrackOffsetSnapshot

TRACK_OFFSET_DATABASE_NAME = "track_offsets.sqlite3"
TRACK_OFFSET_SCHEMA_VERSION = 2
# Upper bound on stored corrections; the least recently updated rows go first.
TRACK_OFFSET_MAX_ENTRIES = 5000

_SCHEMA = """
CREATE TABLE IF NOT EXISTS track_offsets (
    track_title TEXT NOT NULL,
    track_artist TEXT NOT NULL,
    track_album TEXT NOT NULL,
    track_duration_s INTEGER NOT NULL,
    lyrics_source_id TEXT NOT NULL,
    lyrics_song_id TEXT NOT NULL,
    lyrics_digest TEXT NOT NULL,
    offset_ms INTEGER NOT NULL CHECK (offset_ms BETWEEN -10000 AND 10000),
    updated_at REAL NOT NULL,
    PRIMARY KEY (
        track_title,
        track_artist,
        track_album,
        track_duration_s,
        lyrics_source_id,
        lyrics_song_id,
        lyrics_digest
    )
) WITHOUT ROWID;
"""


def state_dir() -> Path:
    """Return the XDG state directory used for user-owned runtime state."""
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return Path(base) / "n501.karaoke"


def track_offset_path() -> Path:
    """Return the default SQLite path for lyric timing corrections."""
    return state_dir() / TRACK_OFFSET_DATABASE_NAME


class TrackOffsetStoreError(RuntimeError):
    """A track-offset database could not be read or written."""


class TrackOffsetStore:
    """Own SQLite schema and row conversion for track timing corrections."""

    def __init__(self, path: Path | None = None, max_entries: int = TRACK_OFFSET_MAX_ENTRIES) -> None:
        """Create a storage owner without opening a database connection."""
        if max_entries < 1:
            raise ValueError("track offset store needs room for at least one entry")
        self._path = path
        self._max_entries = max_entries

    def load(self) -> TrackOffsetSnapshot:
        """Load all valid corrections, creating the schema when needed."""
        target = self._target()
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            with self._connect(target) as connection:
                self._ensure_schema(connection)
                rows = connection.execute(
                    "SELECT track_title, track_artist, track_album, track_duration_s, "
                    "lyrics_source_id, lyrics_song_id, lyrics_digest, offset_ms "
                    "FROM track_offsets ORDER BY updated_at ASC"
                ).fetchall()
        except (OSError, sqlite3.Error) as exc:
            raise TrackOffsetStoreError("track offset database load failed") from exc
        entries: list[TrackOffsetEntry] = []
        identities: set[TrackOffsetKey] = set()
        for row in rows:
            try:
                key = TrackOffsetKey(
                    row[0],
                    row[1],
                    row[2],
                    _optional_duration(row[3]),
                    row[4],
                    _optional_song_id(row[5]),
                    row[6],
                )
                if key in identities:
                    continue
                identities.add(key)
                entries.append(TrackOffsetEntry(key, row[7]))
            except (TypeError, ValueError):
                # The schema constrains new writes; this keeps a manually damaged
                # row from making every valid correction unavailable at startup.
                continue
        return TrackOffsetSnapshot(tuple(entries))

    def upsert(self, entry: TrackOffsetEntry) -> None:
        """Insert or replace one validated correction without rewriting other rows."""
        if not isinstance(entry, TrackOffsetEntry):
            raise TypeError("track offset store requires a TrackOffsetEntry")
        target = self._target()
        try:
            target.parent.mkdir(parents=True, exist_ok=True)
            with self._connect(target) as connection:
                self._ensure_schema(connection)
                connection.execute(
                    "INSERT INTO track_offsets ("
                    "track_title, track_artist, track_album, track_duration_s, lyrics_source_id, "
                    "lyrics_song_id, lyrics_digest, offset_ms, updated_at"
                    ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
                    "ON CONFLICT(track_title, track_artist, track_album, track_duration_s, "
                    "lyrics_source_id, lyrics_song_id, lyrics_digest) DO UPDATE SET "
                    "offset_ms = excluded.offset_ms, updated_at = excluded.updated_at",
                    _row_values(entry, time()),
                )
                connection.execute(
                    "DELETE FROM track_offsets WHERE (track_title, track_artist, track_album, "
                    "track_duration_s, lyrics_source_id, lyrics_song_id, lyrics_digest) IN ("
                    "SELECT track_title, track_artist, track_album, track_duration_s, "
                    "lyrics_source_id, lyrics_song_id, lyrics_digest FROM track_offsets "
                    "ORDER BY updated_at DESC LIMIT -1 OFFSET ?)",
                    (self._max_entries,),
                )
        except (OSError, sqlite3.Error) as exc:
            raise TrackOffsetStoreError("track offset database upsert failed") from exc

    def _target(self) -> Path:
        return track_offset_path() if self._path is None else self._path

    @staticmethod
    def _connect(target: Path) -> sqlite3.Connection:
        connection = sqlite3.connect(target, timeout=3.0)
        connection.execute("PRAGMA foreign_keys = ON")
        return connection

    @staticmethod
    def _ensure_schema(connection: sqlite3.Connection) -> None:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version not in (0, 1, TRACK_OFFSET_SCHEMA_VERSION):
            raise sqlite3.DatabaseError(f"unsupported track offset schema version: {version}")
        if version == 1:
            TrackOffsetStore._migrate_v1(connection)
            return
        connection.executescript(_SCHEMA)
        if version == 0:
            connection.execute(f"PRAGMA user_version = {TRACK_OFFSET_SCHEMA_VERSION}")

    @staticmethod
    def _migrate_v1(connection: sqlite3.Connection) -> None:
        """Migrate the pre-second-normalized table without losing saved corrections."""
        rows = connection.execute(
            "SELECT track_title, track_artist, track_album, track_duration_ms, "
            "lyrics_source_id, lyrics_song_id, lyrics_digest, offset_ms, updated_at "
            "FROM track_offsets ORDER BY updated_at ASC"
        ).fetchall()
        connection.execute("ALTER TABLE track_offsets RENAME TO track_offsets_v1")
        connection.execute(_SCHEMA)
        for row in rows:
            try:
                key = TrackOffsetKey(
                    row[0],
                    row[1],
                    row[2],
                    _legacy_duration(row[3]),
                    row[4],
                    _optional_song_id(row[5]),
                    row[6],
                )
                entry = TrackOffsetEntry(key, row[7])
            except (TypeError, ValueError):
                continue
            connection.execute(
                "INSERT INTO track_offsets ("
                "track_title, track_artist, track_album, track_duration_s, lyrics_source_id, "
                "lyrics_song_id, lyrics_digest, offset_ms, updated_at"
                ") VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?) "
                "ON CONFLICT(track_title, track_artist, track_album, track_duration_s, "
                "lyrics_source_id, lyrics_song_id, lyrics_digest) DO UPDATE SET "
                "offset_ms = excluded.offset_ms, updated_at = excluded.updated_at",
                _row_values(entry, row[8]),
            )
        connection.execute("DROP TABLE track_offsets_v1")
        connection.execute(f"PRAGMA user_version = {TRACK_OFFSET_SCHEMA_VERSION}")


def _row_values(entry: TrackOffsetEntry, updated_at: float) -> tuple[object, ...]:
    """Convert one validated domain entry to SQLite's non-null identity columns."""
    key = entry.key
    return (
        key.track_title,
        key.track_artist,
        key.track_album,
        -1 if key.track_duration_s is None else key.track_duration_s,
        key.lyrics_source_id,
        "" if key.lyrics_song_id is None else key.lyrics_song_id,
        key.lyrics_digest,
        entry.offset_ms,
        updated_at,
    )


def _optional_duration(value: object) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool):
        return None if value == -1 else value
    return None


def _legacy_duration(value: object) -> int | None:
    if isinstance(value, int) and not isinstance(value, bool):
        return None if value < 0 else round(value / 1000)
    return None


def _optional_song_id(value: object) -> str | None:
    return value if isinstance(value, str) and value else None


__all__ = [
    "TRACK_OFFSET_DATABASE_NAME",
    "TRACK_OFFSET_SCHEMA_VERSION",
    "TrackOffsetStore",
    "TrackOffsetStoreError",
    "state_dir",
    "track_offset_path",
]
