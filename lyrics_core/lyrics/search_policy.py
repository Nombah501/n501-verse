"""Stable result-budget policy for manual lyric selection."""

from typing import Final

MANUAL_SEARCH_RESULTS_PER_PROVIDER: Final = 30
"""Maximum candidates a single provider may prepare for manual selection."""

MANUAL_SEARCH_RESULTS_TOTAL: Final = 90
"""Maximum candidates exposed by one manual search across all providers."""


__all__ = ["MANUAL_SEARCH_RESULTS_PER_PROVIDER", "MANUAL_SEARCH_RESULTS_TOTAL"]
