"""Which words in a title mark a different recording of the same song.

Publisher decoration lives in title_grammar; this module answers only whether
two titles name the same performance, which is what decides if one's lyric
sheet fits the other's timings.
"""

from __future__ import annotations

import re

VERSION_TAGS = {
    # "acounstic" is not a typo here: it is how the upload spells it, and the
    # misspelling is what the title actually carries.
    "acoustic": ("acoustic", "acounstic", "unplugged", "原声版", "原聲版"),
    # 歌ってみた is the Japanese "I tried singing it" — a user cover, so the words
    # are the same but the performance and its timings are not.
    "cover": ("cover", "翻唱", "歌ってみた"),
    # An alternate vocalist for the same song (Vocaloid uploads name the singer).
    # A re-sung 女声版/男声版 keeps the words and changes every timing, which is what
    # let 不谓侠(女声版) stand in for 不谓侠 when no artist was reported.
    "alt_vocal": ("バーチャル・シンガーver", "バーチャルシンガーver", "女声版", "女聲版", "男声版", "男聲版"),
    "demo": ("demo",),
    "edit": ("edit",),
    "extended": ("extended",),
    # 钢琴版 and 纯音乐 carry no words at all, so accepting one hands the overlay a
    # lyric sheet for a recording that never sings it.
    "instrumental": (
        "instrumental", "instrumental version", "off vocal", "off-vocal", "伴奏",
        "钢琴版", "鋼琴版", "纯音乐版", "純音樂版", "纯音乐", "純音樂",
    ),
    "karaoke": ("karaoke", "卡拉ok"),
    # A broadcast edit runs about ninety seconds against a full-length recording,
    # so its words are a subset and every timing after the cut is wrong.
    "tv_size": ("tv size", "tv-size", "tvsize", "tv ver", "tvサイズ", "テレビサイズ"),
    "live": ("live", "live版", "现场", "現場"),
    "remaster": ("remaster", "remastered"),
    "remix": ("remix", "dj版"),
    "guitar": ("吉他版",),
    "strum": ("弹唱版", "彈唱版"),
    "opera": ("戏腔版", "戲腔版"),
    "cantonese": ("粤语版", "粵語版"),
    # The slowed/sped/reverb family is what a re-upload channel actually publishes,
    # and the timing differs from the studio take, so the lyrics do not line up.
    "sped_up": ("sped up", "sped-up", "spedup", "加速版"),
    "slowed": ("slowed", "slowed down", "slowed + reverb", "slowed and reverb", "慢速版", "降速版"),
    "reverb": ("reverb", "reverbed"),
    "nightcore": ("nightcore",),
    "rhythm": ("律动版", "律動版"),
    "rnb": ("r&b版", "r&b心碎版"),
    "smoky": ("烟嗓版", "煙嗓版"),
    "full": ("full version",),
    "opening": ("opening title version",),
    "choreography": ("choreography ver", "choreography version"),
}
# Tags that change the recording but NOT the lyrics: a remaster has the same
# words as the studio take, so it must not force a version conflict that rejects
# the only correct candidate. (live/acoustic/instrumental/remix/etc. can differ.)
# A remaster and a choreography video are the same performance: the words and
# their timings are the studio take's, so neither may reject the only
# candidate that has lyrics at all.
LYRIC_NEUTRAL_TAGS = frozenset({"remaster", "choreography"})


# Compiled marker matchers are reused for every candidate; CJK markers use literal
# matching while Latin markers use ASCII-letter boundaries to avoid substring hits.
def _version_pattern(marker: str) -> re.Pattern[str]:
    escaped = re.escape(marker)
    if any(char.isascii() and char.isalpha() for char in marker):
        return re.compile(r"(?<![A-Za-z])" + escaped + r"(?![A-Za-z])", re.IGNORECASE)
    return re.compile(escaped)

VERSION_TAG_PATTERNS = {
    tag: tuple(_version_pattern(marker) for marker in markers)
    for tag, markers in VERSION_TAGS.items()
}
VERSION_SUFFIX_PATTERNS = tuple(
    _version_pattern(marker) for markers in VERSION_TAGS.values() for marker in markers
)


def extract_version_tags(value: str) -> set[str]:
    return {
        tag
        for tag, patterns in VERSION_TAG_PATTERNS.items()
        if any(pattern.search(value) for pattern in patterns)
    }


__all__ = [
    "LYRIC_NEUTRAL_TAGS",
    "VERSION_SUFFIX_PATTERNS",
    "VERSION_TAGS",
    "VERSION_TAG_PATTERNS",
    "extract_version_tags",
]
