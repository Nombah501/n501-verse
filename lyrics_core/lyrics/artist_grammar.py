"""Normalize performer metadata independently from title matching policy.

The functions in this module are stateless grammar transformations. They split
provider artist fields, expose the primary performer, and produce alternate
readings for fused bilingual channel names; match confidence remains in
``lyrics.match``.
"""

from __future__ import annotations

import re
from unicodedata import normalize as unicode_normalize

from .title_grammar import cjk_runs, latin_tokens, normalize

_ARTIST_SEPARATOR = re.compile(
    r"\s*(?:,|/|&|;|、|，|\band\b|\bwith\b|\bfeat(?:uring)?\b\.?|\bft\b\.?)\s*",
    re.IGNORECASE,
)
# "和" is a CJK artist-list separator only when it joins two substantial runs.
# The katakana middle dot stays inside names such as テイラー・スウィフト.
_AND_SEPARATOR = re.compile(r"(?<=\S\S)和(?=\S\S)|\s+和\s+")
_TOPIC_CHANNEL_SUFFIX = re.compile(r"\s*-\s*Topic\s*$", re.IGNORECASE)


def _artist_parts(artist: str) -> tuple[str, ...]:
    value = unicode_normalize("NFKC", artist).strip()
    parts: list[str] = []
    for chunk in _ARTIST_SEPARATOR.split(value):
        parts.extend(_AND_SEPARATOR.split(chunk))
    return tuple(part.strip() for part in parts if part.strip())


def artist_tokens(artist: str) -> frozenset[str]:
    """Return normalized, de-duplicated performer tokens."""
    return frozenset(token for token in (normalize(part) for part in _artist_parts(artist)) if token)


def primary_artist(artist: str) -> str:
    """Return the first performer in a provider's artist list."""
    parts = _artist_parts(artist)
    return parts[0].strip() if parts else artist.strip()


def artist_variants(artist: str) -> tuple[str, ...]:
    """Return CJK and Latin readings of a fused bilingual performer name."""
    halves = (
        " ".join(cjk_runs(artist)).strip(),
        " ".join(latin_tokens(artist)).strip(),
    )
    return tuple(half for half in dict.fromkeys(halves) if half and half != artist.strip())


def performing_artist(artist: str) -> str:
    """Remove the ``- Topic`` channel suffix from an auto-generated artist name."""
    return _TOPIC_CHANNEL_SUFFIX.sub("", artist).strip()


__all__ = ["artist_tokens", "artist_variants", "performing_artist", "primary_artist"]
