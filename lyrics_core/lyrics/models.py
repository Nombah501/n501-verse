"""Canonical lyric documents shared by parsers, sources, and display projection."""

from __future__ import annotations

import math
from dataclasses import dataclass
from enum import StrEnum


class TimingKind(StrEnum):
    """The timing granularity guaranteed by a lyric document."""

    LINE = "Line"
    WORD = "Word"


class LyricsOrigin(StrEnum):
    """Describe how the currently displayed lyric document entered Kotonoha."""

    NETWORK = "network"
    CACHE = "cache"
    LIVE = "live"
    SIDECAR = "sidecar"
    EMBEDDED = "embedded"
    ADAPTER = "adapter"
    MANUAL = "manual"


class LyricsCacheState(StrEnum):
    """Describe the persistence relationship of the displayed lyric document."""

    NONE = "none"
    FROM_CACHE = "from-cache"
    MANUAL = "manual"


@dataclass(frozen=True)
class LyricWord:
    """One optional timed word inside a lyric line."""

    start: float | None
    end: float | None
    text: str


@dataclass(frozen=True)
class LyricLine:
    """One timed lyric line in canonical form."""

    index: int
    id: str
    start: float
    end: float
    text: str
    translation: str
    words: tuple[LyricWord, ...] = ()

    @property
    def has_word_timing(self) -> bool:
        """Whether at least one word carries a complete timing span."""
        return any(word.start is not None and word.end is not None for word in self.words)


@dataclass(frozen=True)
class LyricsDocument:
    """A source-neutral timed lyric artifact, before current-line projection."""

    source_id: str
    source_name: str | None = None
    song_id: str | None = None
    timing: TimingKind | None = None
    language: str | None = None
    title: str | None = None
    artist: str | None = None
    album: str | None = None
    duration_s: float | None = None
    lines: tuple[LyricLine, ...] = ()
    origin: LyricsOrigin = LyricsOrigin.NETWORK
    cache_state: LyricsCacheState = LyricsCacheState.NONE

    @property
    def has_word_timing(self) -> bool:
        """Whether the document contains usable word timing."""
        return self.timing is TimingKind.WORD and any(line.has_word_timing for line in self.lines)


def validate_document(document: LyricsDocument) -> None:
    """Validate the public timing invariants of a parsed lyric document.

    Raises:
        ValueError: if source identity, numeric bounds, ordering, or word spans are invalid.
    """
    if not document.source_id:
        raise ValueError("lyrics document has no source")
    if document.duration_s is not None and (
        not math.isfinite(document.duration_s) or document.duration_s <= 0.0
    ):
        raise ValueError("lyrics document has an invalid duration")

    previous_start = -math.inf
    for line in document.lines:
        if not math.isfinite(line.start) or not math.isfinite(line.end) or line.start < 0.0 or line.end < line.start:
            raise ValueError("lyrics document has an invalid line span")
        if line.start < previous_start:
            raise ValueError("lyrics document lines are not ordered")
        previous_start = line.start
        for word in line.words:
            if word.start is None and word.end is None:
                continue
            if word.start is None or word.end is None:
                raise ValueError("lyrics document has a partial word span")
            if not math.isfinite(word.start) or not math.isfinite(word.end):
                raise ValueError("lyrics document has a non-finite word span")
            if word.start < 0.0 or word.end < word.start:
                raise ValueError("lyrics document has an invalid word span")
