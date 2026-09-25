"""Decode Kugou KRC lyrics into word-timed :class:`LyricLine` objects."""

from __future__ import annotations

import re
import zlib

from .models import LyricLine, LyricWord
from .payload import decompress_capped

KRC_MAGIC = b"krc1"
# Kugou's documented KRC stream key; it is part of the file format, not a secret.
KRC_XOR_KEY = bytes((64, 71, 97, 119, 94, 50, 116, 71, 81, 54, 49, 45, 206, 210, 110, 105))
# Milliseconds within one song: eight digits is over a day, and an unbounded run
# reaches the division below as an int too large to convert to a float, which
# raises OverflowError out of the parser. Bounded here, at the boundary, so an
# absurd timestamp simply fails to match and its line is skipped like any other
# malformed one.
_LINE_HEAD = re.compile(r"^\[(\d{1,8}),(\d{1,8})\]")
_WORD = re.compile(r"<(\d{1,8}),(\d{1,8}),\d+>([^<]*)")


def _decode_krc(body: bytes) -> str | None:
    if not body.startswith(KRC_MAGIC):
        return None
    encrypted = body[len(KRC_MAGIC) :]
    try:
        decoded = bytes(value ^ KRC_XOR_KEY[index % len(KRC_XOR_KEY)] for index, value in enumerate(encrypted))
        return decompress_capped(decoded, "KRC").decode("utf-8")
    except (zlib.error, UnicodeDecodeError, ValueError):
        return None


def parse_krc(body: bytes) -> list[LyricLine]:
    """Decode a base64-decoded KRC body, returning only lines with word timing."""
    text = _decode_krc(body)
    if text is None:
        return []

    lines: list[LyricLine] = []
    for raw in text.splitlines():
        head = _LINE_HEAD.match(raw)
        if head is None:
            continue
        line_start_ms = int(head.group(1))
        line_start = line_start_ms / 1000.0
        line_end = (line_start_ms + int(head.group(2))) / 1000.0
        words: list[LyricWord] = []
        parts: list[str] = []
        for match in _WORD.finditer(raw, head.end()):
            word_start_ms = line_start_ms + int(match.group(1))
            word_end_ms = word_start_ms + int(match.group(2))
            word_text = match.group(3)
            words.append(LyricWord(start=word_start_ms / 1000.0, end=word_end_ms / 1000.0, text=word_text))
            parts.append(word_text)
        text_line = "".join(parts)
        if not text_line.strip() or not words:
            continue
        index = len(lines)
        lines.append(
            LyricLine(
                index=index,
                id=f"L{index}",
                start=line_start,
                end=line_end,
                text=text_line,
                translation="",
                words=tuple(words),
            )
        )
    return lines
