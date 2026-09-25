"""Adapters that turn resolved lyric artifacts into canonical lyric documents."""

from __future__ import annotations

from collections.abc import Iterable

from .models import (
    LyricLine,
    LyricsCacheState,
    LyricsDocument,
    LyricsOrigin,
    TimingKind,
    validate_document,
)


class LyricsDocumentAdapter:
    """Normalize provider output and attach source-owned document metadata."""

    def adapt(
        self,
        lines: Iterable[LyricLine],
        *,
        source_id: str,
        source_name: str | None = None,
        song_id: str | None = None,
        language: str | None = None,
        title: str | None = None,
        artist: str | None = None,
        album: str | None = None,
        duration_s: float | None = None,
        origin: LyricsOrigin = LyricsOrigin.NETWORK,
        cache_state: LyricsCacheState = LyricsCacheState.NONE,
    ) -> LyricsDocument:
        """Build and validate one immutable source-neutral lyric document."""
        normalized_lines = tuple(lines)
        timing = (
            TimingKind.WORD
            if any(line.has_word_timing for line in normalized_lines)
            else TimingKind.LINE
            if normalized_lines
            else None
        )
        document = LyricsDocument(
            source_id=source_id,
            source_name=source_name,
            song_id=song_id,
            timing=timing,
            language=language,
            title=title,
            artist=artist,
            album=album,
            duration_s=duration_s,
            lines=normalized_lines,
            origin=origin,
            cache_state=cache_state,
        )
        validate_document(document)
        return document


__all__ = ["LyricsDocumentAdapter"]
