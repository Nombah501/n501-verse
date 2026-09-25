"""Bounds on what an untrusted lyric payload is allowed to cost.

Every provider here fetches from a third party over the network, and one of them
also decompresses what it receives. A timeout bounds how long a response may take,
not how large it may become: a server that streams steadily stays well inside the
limit while the buffered body grows without end, and a compressed body is smaller
still on the wire than in memory. So size is bounded separately, in one place, and
the providers say what they are reading rather than each carrying its own ceiling.
"""

from __future__ import annotations

import json
import zlib

from .http import LyricsResponse

#: Lyrics for one song are a few kilobytes; a search result is a few hundred.
MAX_RESPONSE_BYTES = 2 * 1024 * 1024
#: The decompressed form of a lyric payload, which the wire size does not bound.
MAX_DECOMPRESSED_BYTES = 4 * 1024 * 1024


#: How much is taken from the stream per read. Only a buffer size; the ceiling is
#: MAX_RESPONSE_BYTES and is enforced across the whole body.
_CHUNK_BYTES = 64 * 1024


async def read_capped(
    response: LyricsResponse,
    source: str,
    *,
    max_bytes: int = MAX_RESPONSE_BYTES,
) -> bytes:
    """Return the whole body, refusing one larger than ``max_bytes``.

    Read in a loop to end of stream. A single ``content.read(n)`` returns only what
    has arrived so far, not ``n`` bytes: measured against a server streaming 307KB
    in 8KB writes, one call returned 114KB, and the truncated body then failed to
    parse — so a lyric or search result larger than one buffer would have been lost
    rather than capped.
    """
    if type(max_bytes) is not int or max_bytes <= 0:
        raise ValueError("response byte limit must be a positive integer")
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await response.content.read(_CHUNK_BYTES)
        if not chunk:
            break
        total += len(chunk)
        if total > max_bytes:
            raise ValueError(f"{source} response exceeded {max_bytes} bytes")
        chunks.append(chunk)
    return b"".join(chunks)


async def read_json_capped(
    response: LyricsResponse,
    source: str,
    *,
    max_bytes: int = MAX_RESPONSE_BYTES,
) -> object:
    """Return the body parsed as JSON, refusing an oversized one.

    Used instead of ``response.json()``, which buffers whatever arrives.
    """
    body = await read_capped(response, source, max_bytes=max_bytes)
    try:
        return json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ValueError(f"{source} response is not JSON: {exc}") from exc


def decompress_capped(data: bytes, source: str) -> bytes:
    """Inflate ``data``, refusing a stream that expands past the ceiling.

    zlib.decompress allocates whatever the stream unpacks to. Measured on this
    project's own KRC path, 203KB of valid compressed body expanded to 200MB and
    took the process's resident size with it, so the output is read in bounded
    steps and a stream with more to give is rejected rather than finished.
    """
    machine = zlib.decompressobj()
    out = machine.decompress(data, MAX_DECOMPRESSED_BYTES)
    if not machine.eof or machine.unconsumed_tail:
        raise ValueError(f"{source} payload expands past {MAX_DECOMPRESSED_BYTES} bytes")
    return out
