"""Explicit translation alignment transforms for canonical lyric documents."""

from __future__ import annotations

import math
from bisect import bisect_left
from collections.abc import Sequence
from dataclasses import replace

from .models import LyricLine, LyricsDocument


class TranslationMerger:
    """Apply timestamp or positional translation alignment with one contract."""

    def __init__(self, tolerance_s: float = 0.4) -> None:
        if not math.isfinite(tolerance_s) or tolerance_s < 0.0:
            raise ValueError("translation tolerance must be finite and non-negative")
        self._tolerance_s = tolerance_s

    @property
    def tolerance_s(self) -> float:
        """Return the maximum timestamp distance accepted by this merger."""
        return self._tolerance_s

    def merge_by_timestamp(
        self,
        base: Sequence[LyricLine],
        translation: Sequence[LyricLine],
    ) -> tuple[LyricLine, ...]:
        """Attach the nearest translation line without quadratic scanning."""
        if not translation:
            return tuple(base)
        ordered = sorted(translation, key=lambda item: item.start)
        starts = [item.start for item in ordered]
        output: list[LyricLine] = []
        for line in base:
            index = bisect_left(starts, line.start)
            best_text: str | None = None
            best_delta = self._tolerance_s
            for neighbour in (index - 1, index):
                if 0 <= neighbour < len(ordered):
                    delta = abs(starts[neighbour] - line.start)
                    if delta <= best_delta:
                        best_delta = delta
                        best_text = ordered[neighbour].text
            output.append(replace(line, translation=best_text) if best_text else line)
        return tuple(output)

    def merge_by_index(self, document: LyricsDocument, translations: Sequence[str]) -> LyricsDocument:
        """Attach provider-returned line-ordered text without changing timing."""
        lines = tuple(
            replace(line, translation=translations[index])
            if index < len(translations)
            else line
            for index, line in enumerate(document.lines)
        )
        return replace(document, lines=lines)


__all__ = ["TranslationMerger"]
