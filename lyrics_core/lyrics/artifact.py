"""Provider-neutral lyrics fetched from a stable provider song identifier."""

from __future__ import annotations

from dataclasses import dataclass

from .match import Candidate, MatchConfidence
from .models import LyricLine


@dataclass(frozen=True)
class LyricsArtifact:
    provider: str
    provider_song_id: str
    title: str
    artist: str
    album: str
    duration_s: float | None
    payload: dict[str, str]
    lines: tuple[LyricLine, ...]
    confidence: MatchConfidence

    @property
    def candidate(self) -> Candidate:
        return Candidate(
            song_id=self.provider_song_id,
            title=self.title,
            artist=self.artist,
            duration_s=self.duration_s,
            album=self.album,
        )
