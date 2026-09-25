"""Build additional search readings from noisy publisher titles."""

from __future__ import annotations

import re

from .title_grammar import (
    cjk_runs,
    debracket_query_text,
    flatten_title_delimiters,
    latin_tokens,
    normalize_query_whitespace,
    remove_upload_noise,
)

# A featured performer is credited inside the title and is not part of the song
# name. The credit ends at the next title separator; ``with`` is intentionally not
# treated as a marker because it is part of ordinary song names.
_FEAT_CREDIT = re.compile(r"\s*\b(?:feat|ft|featuring)\b\.?\s*[^-–—()\[\]【】]*", re.IGNORECASE)


def noisy_title_queries(title: str) -> tuple[str, ...]:
    """Return fuzzy-search readings after removing upload decoration."""
    stripped = remove_upload_noise(debracket_query_text(title))
    # Preserve the credited form before flattening separators: some catalogues index
    # the featured-performer spelling while others index the song without it.
    credited = stripped
    stripped = flatten_title_delimiters(stripped)
    queries: list[str] = []

    combined = normalize_query_whitespace(stripped).strip()
    if len(combined) >= 2:
        queries.append(combined)
    uncredited = normalize_query_whitespace(
        flatten_title_delimiters(_FEAT_CREDIT.sub(" ", credited))
    ).strip()
    if len(uncredited) >= 2 and uncredited != combined:
        queries.append(uncredited)

    cjk = normalize_query_whitespace(" ".join(cjk_runs(stripped))).strip()
    if len(cjk) >= 2:
        queries.append(cjk)
    has_cjk = bool(cjk)
    latin_values = list(latin_tokens(stripped))
    # When CJK is present, a trailing all-caps channel name is noise. For pure Latin
    # titles retain an all-caps title such as TALK THAT TALK as one reading.
    while (
        len(latin_values) > 2
        and latin_values[-1].isupper()
        and len(latin_values[-1]) >= 2
        and (has_cjk or not all(token.isupper() for token in latin_values[:-1]))
    ):
        latin_values.pop()
    latin = " ".join(latin_values).strip()
    if len(latin) >= 2:
        queries.append(latin)
    return tuple(dict.fromkeys(queries))


__all__ = ["noisy_title_queries"]
