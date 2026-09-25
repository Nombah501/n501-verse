"""One-time, read-only import of user selections from Kotonoha stores."""

from __future__ import annotations

import os
import sqlite3
import tempfile
import time
from contextlib import closing
from pathlib import Path
from urllib.parse import quote

from .lyrics.cache.storage import CACHE_SCHEMA_VERSION, LyricsCacheStorage
from .lyrics.title_grammar import NORMALIZER_VERSION
from .state.track_offset_store import TrackOffsetStore

_CACHE_COLUMNS = (
    "provider, provider_song_id, title, artist, album, mode, duration_s, "
    "payload_json, fetched_at, last_accessed, schema_version, normalizer_version"
)
_OFFSET_COLUMNS = (
    "track_title, track_artist, track_album, track_duration_s, lyrics_source_id, "
    "lyrics_song_id, lyrics_digest, offset_ms, updated_at"
)


def kotonoha_cache_path() -> Path:
    base = os.environ.get("XDG_CACHE_HOME") or os.path.join(os.path.expanduser("~"), ".cache")
    return Path(base) / "kotonoha" / "lyrics.sqlite3"


def kotonoha_offset_path() -> Path:
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return Path(base) / "kotonoha" / "track_offsets.sqlite3"

def _source_uri(source: Path) -> str:
    with source.open("rb") as handle:
        header = handle.read(20)
    if len(header) < 20 or header[:16] != b"SQLite format 3\x00":
        raise ValueError("invalid sqlite header")
    modes = header[18:20]
    query = "mode=ro"
    if modes == b"\x02\x02":
        wal = Path(str(source) + "-wal").exists()
        shm = Path(str(source) + "-shm").exists()
        if wal != shm:
            raise ValueError("incomplete WAL sidecars")
        if not wal:
            query += "&immutable=1"
    elif modes != b"\x01\x01":
        raise ValueError("unsupported sqlite journal mode")
    return f"file:{quote(str(source), safe='/')}?{query}"


def _clear_stale_temporaries(parent: Path) -> None:
    cutoff = time.time() - 600
    for path in parent.glob(".kotonoha-import-*"):
        try:
            if path.is_file() and path.stat().st_mtime < cutoff:
                path.unlink()
        except FileNotFoundError:
            pass  # Another process already cleaned it.


def _import_store(dest: Path, source: Path, columns: str, table: str, predicate: str) -> list[str]:
    # An existing store means the import already happened (or was skipped):
    # return before directory setup so its failures cannot re-warn forever,
    # but still sweep temporaries a crashed earlier import may have left.
    if dest.exists():
        try:
            _clear_stale_temporaries(dest.parent)
        except OSError:
            pass
        return []
    tmp: Path | None = None
    try:
        dest.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        os.chmod(dest.parent, 0o700)
        _clear_stale_temporaries(dest.parent)
        if dest.exists():
            return []
        try:
            source.stat()
        except FileNotFoundError:
            return []
        fd, name = tempfile.mkstemp(prefix=".kotonoha-import-", dir=dest.parent)
        os.close(fd)
        tmp = Path(name)
        if table == "lyrics":
            with closing(LyricsCacheStorage(tmp, max_entries=1000)._connect()):
                pass
        else:
            with closing(TrackOffsetStore._connect(tmp)) as connection:
                TrackOffsetStore._ensure_schema(connection)
                connection.commit()
        uri = _source_uri(source)
        with closing(sqlite3.connect(uri, uri=True, timeout=0.5)) as original, closing(sqlite3.connect(tmp)) as target:
            rows = original.execute(f"SELECT {columns} FROM {table} {predicate}")
            target.executemany(
                f"INSERT INTO {table} ({columns}) VALUES ({', '.join('?' for _ in columns.split(', '))})",
                rows,
            )
            target.commit()
        os.chmod(tmp, 0o600)
        try:
            os.link(tmp, dest)
        except FileExistsError:
            pass  # Another process created its store first; never overwrite it.
        except OSError:
            # No hard links on this filesystem: rename is the fallback. The
            # exists-check leaves a tiny check-then-act window in which a store
            # created concurrently by another process could be replaced.
            if not dest.exists():
                os.rename(tmp, dest)
        return []
    except Exception:
        return ["kotonoha_import_failed"]
    finally:
        if tmp is not None:
            tmp.unlink(missing_ok=True)


def ensure_cache_store(dest: Path) -> list[str]:
    return _import_store(
        dest, kotonoha_cache_path(), _CACHE_COLUMNS, "lyrics",
        "WHERE mode = 'manual' AND schema_version = " + str(CACHE_SCHEMA_VERSION)
        + " AND normalizer_version = " + str(NORMALIZER_VERSION)
        + " ORDER BY last_accessed DESC LIMIT 1000",
    )


def ensure_offset_store(dest: Path) -> list[str]:
    return _import_store(dest, kotonoha_offset_path(), _OFFSET_COLUMNS, "track_offsets", "")
