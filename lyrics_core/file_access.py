"""Bounded reads for paths received from external or user-controlled sources."""

from __future__ import annotations

import os
import stat
from dataclasses import dataclass
from enum import StrEnum
from pathlib import Path


class RegularFileReadFailure(StrEnum):
    """Reason a bounded regular-file read did not produce bytes."""

    MISSING = "missing"
    OPEN_FAILED = "open_failed"
    NOT_REGULAR = "not_regular"
    TOO_LARGE = "too_large"
    READ_FAILED = "read_failed"
    CLOSE_FAILED = "close_failed"


@dataclass(frozen=True, slots=True)
class RegularFileReadResult:
    """Typed result of a bounded regular-file read."""

    data: bytes | None
    failure: RegularFileReadFailure | None = None

    def __post_init__(self) -> None:
        if (self.data is None) == (self.failure is None):
            raise ValueError("a regular-file result must contain data or one failure")

    @property
    def succeeded(self) -> bool:
        """Return whether the complete file content was read."""
        return self.data is not None


class BoundedRegularFileReader:
    """Read complete ordinary files without blocking or exceeding a byte limit."""

    def __init__(self, max_bytes: int) -> None:
        if max_bytes <= 0:
            raise ValueError("max_bytes must be positive")
        self._max_bytes = max_bytes

    def read(self, path: Path) -> RegularFileReadResult:
        """Read ``path`` through one checked descriptor, or return a failure reason."""
        try:
            descriptor = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except FileNotFoundError:
            return RegularFileReadResult(None, RegularFileReadFailure.MISSING)
        except OSError:
            return RegularFileReadResult(None, RegularFileReadFailure.OPEN_FAILED)

        result: RegularFileReadResult
        try:
            try:
                metadata = os.fstat(descriptor)
                if not stat.S_ISREG(metadata.st_mode):
                    result = RegularFileReadResult(None, RegularFileReadFailure.NOT_REGULAR)
                elif metadata.st_size > self._max_bytes:
                    result = RegularFileReadResult(None, RegularFileReadFailure.TOO_LARGE)
                else:
                    result = self._read_checked_descriptor(descriptor)
            except OSError:
                result = RegularFileReadResult(None, RegularFileReadFailure.READ_FAILED)
        finally:
            try:
                os.close(descriptor)
            except OSError:
                result = RegularFileReadResult(None, RegularFileReadFailure.CLOSE_FAILED)
        return result

    def _read_checked_descriptor(self, descriptor: int) -> RegularFileReadResult:
        """Read one descriptor and reject a file that grows past the bound."""
        chunks: list[bytes] = []
        total = 0
        while True:
            chunk = os.read(descriptor, 1 << 16)
            if not chunk:
                return RegularFileReadResult(b"".join(chunks))
            total += len(chunk)
            if total > self._max_bytes:
                return RegularFileReadResult(None, RegularFileReadFailure.TOO_LARGE)
            chunks.append(chunk)


__all__ = [
    "BoundedRegularFileReader",
    "RegularFileReadFailure",
    "RegularFileReadResult",
]
