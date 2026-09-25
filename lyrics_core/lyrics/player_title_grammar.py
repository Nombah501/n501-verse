"""Normalize browser and player chrome wrapped around a song title."""

from __future__ import annotations

import re

from .title_grammar import clean_title

_TITLE_BADGE_PREFIX = re.compile(r"^\(\d+\)\s+")
_TITLE_SITE_SUFFIX = re.compile(
    r"(?:\s*[-|–—_]\s*(?:YouTube(?:\s+Music)?|哔哩哔哩|嗶哩嗶哩|bilibili))+\s*$",
    re.IGNORECASE,
)


def clean_player_title(title: str, artist: str = "") -> str:
    """Remove known browser chrome before applying shared title grammar."""
    cleaned = _TITLE_BADGE_PREFIX.sub("", title)
    cleaned = _TITLE_SITE_SUFFIX.sub("", cleaned)
    if artist and artist.casefold() in cleaned.casefold():
        artist_start = cleaned.casefold().find(artist.casefold())
        if artist_start > 0:
            before = cleaned[:artist_start].rstrip()
            remainder = cleaned[artist_start + len(artist) :]
            if remainder.lstrip().startswith(("-", "–", "—", "－")):
                trailing = remainder.lstrip(" \t\r\n-–—－")
                cleaned = artist if before.endswith(("-", "–", "—", "－")) and trailing else trailing
    cleaned = clean_title(cleaned, artist)
    # Never strip a title down to nothing (a page literally titled "YouTube").
    return cleaned.strip() or title.strip()


__all__ = ["clean_player_title"]
