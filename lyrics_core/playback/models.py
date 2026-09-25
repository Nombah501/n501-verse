"""Typed playback facts that cross from a player adapter into application code."""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from enum import StrEnum
from typing import Protocol


class PlaybackStatus(StrEnum):
    """The playback states relevant to lyric timing."""

    PLAYING = "Playing"
    PAUSED = "Paused"
    STOPPED = "Stopped"
    UNKNOWN = "Unknown"

    @classmethod
    def from_wire(cls, value: object) -> PlaybackStatus | None:
        """Return the known status represented by a wire value, or ``None``."""
        if not isinstance(value, str):
            return None
        for status in cls:
            if value == status.value or value.casefold() == status.name.casefold():
                return status
        return None


@dataclass(frozen=True)
class MprisPropertyChange:
    """Normalized MPRIS property notification used by application polling."""

    interface: str
    changed: Mapping[str, object]
    invalidated: tuple[str, ...]


class MprisPlayerPort(Protocol):
    """The bounded player operations required above the D-Bus adapter."""

    async def get_playback_status(self) -> str: ...

    async def get_metadata(self) -> Mapping[str, object]: ...

    async def get_position(self) -> int | float: ...


@dataclass(frozen=True)
class TrackIdentity:
    """A normalized track view with the raw evidence needed by lyric hints."""

    adapter_id: str
    player_id: str
    stable_id: str | None = None
    title: str = ""
    raw_title: str = ""
    artist: str = ""
    album: str = ""
    url: str | None = None
    duration_s: float | None = None

    @property
    def track_ref(self) -> str | None:
        """Return the adapter-scoped stable reference when one exists."""
        if self.stable_id is None or not self.stable_id:
            return None
        return f"{self.adapter_id}:{self.player_id}:{self.stable_id}"


@dataclass(frozen=True)
class PlaybackObservation:
    """One player sample, independent of D-Bus, WebSocket, or Qt objects."""

    adapter_id: str
    player_id: str
    track: TrackIdentity | None
    status: PlaybackStatus
    position_s: float | None
    duration_s: float | None
    observed_at: float
