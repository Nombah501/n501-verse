"""Undo the grammar a publisher wraps around a song name.

Pure text: an upload title carries decoration that no catalogue lists — bracketed
credits, "Official MV", featured performers, a channel's own name fused into the
artist — and every ingest path needs the same rules applied, whether the metadata
arrived over MPRIS, from a browser bridge, or from a player plugin. Nothing here
knows what a candidate or a match is.
"""

from __future__ import annotations

import re
from unicodedata import normalize as unicode_normalize

from .hanzi_fold import fold_to_simplified
from .version_grammar import (
    VERSION_SUFFIX_PATTERNS,
    extract_version_tags,
)

_PARENS = re.compile(r"[\(（\[【『](.*?)[\)）\]】』]")
_DASH_SUFFIX = re.compile(r"\s+[-–—]\s+(.+)$")
_FEAT_SUFFIX = re.compile(r"(?:\b(?:feat(?:uring)?|ft)\b\.?|合作演出\s*[:：]?).*$", re.IGNORECASE)
_TITLE_DASH = re.compile(r"\s+[-–—－]\s+")
_UPLOADER_ARTIST = re.compile(
    r"(?i)(?:channel|頻道|频道|label(?:s)?|records?|music(?:channel)?|vevo|animation|studio|工作室)"
)
_KEEP = re.compile(r"[^\w一-鿿]+")

_TITLE_BARS = re.compile(r"[|｜丨]")
# A closing ’ is never followed by a letter; a contraction's apostrophe always is.
# Without that guard the title ILLIT (아일릿) ‘It’s Me’ Official MV closed on the
# apostrophe in It's and searched for "It s Me’", which matched nothing.
_TITLE_QUOTE = re.compile(r"""[\"“](.+?)[\"”]|‘(.+?)’(?![A-Za-z])|(?<![\w])'(.+)'""")
_TITLE_NOISE_LATIN = re.compile(
    r"(?i)(?<![A-Za-z])(?:official hd mv|official hd|official music video|official lyric video|"
    r"official visualizer|official audio|official video|official mv|video oficial|music video|"
    r"audio|mv)(?![A-Za-z])"
)
_TITLE_NOISE_CJK = re.compile(
    r"動態歌詞Lyrics|动态歌词Lyrics|歌詞字幕|歌词字幕|完整高清音質|完整高清音质|官方高畫質|官方高画质|"
    r"高清MV|高清mv|高清|官方MV|官方mv|Chinese Subs|中文字幕",
    re.IGNORECASE,
)
_TITLE_TAIL_NOISE = re.compile(
    r"(?i)\b(?:music video|one hour|played by|kpop demon hunters|sony animation|league of legends)\b|"
    r"串燒|無間斷|完整聆聽|KTV必唱|在频道内|在頻道內|放鬆音樂"
)

# Compiled marker matchers are reused for every candidate; CJK markers use literal
# matching while Latin markers use ASCII-letter boundaries to avoid substring hits.



NORMALIZER_VERSION = 2


def _fold_latin_accents(text: str) -> str:
    """Strip accents from Latin letters only (é->e, ö->o, ñ->n) so an accented
    title matches its unaccented spelling (Déjà Vu vs Deja Vu, Motörhead vs
    Motorhead). A Japanese dakuten (が = か + U+3099) or any non-Latin base is
    left untouched: only a character whose NFD base is an ASCII letter is folded,
    so kana/hangul/cyrillic/CJK are never mangled."""
    folded: list[str] = []
    for char in text:
        decomposed = unicode_normalize("NFD", char)
        base = decomposed[0]
        folded.append(base if len(decomposed) > 1 and base.isascii() and base.isalpha() else char)
    return "".join(folded)


# The bracket characters alone, for the case where removing bracketed spans
# would leave the title empty.
_BRACKET_EDGES = re.compile(r"[【】\[\]（）()『』「」《》〈〉]+")


def is_bracket_only_title(title: str) -> bool:
    """True when removing bracketed spans would leave the title with no content."""
    return bool(title.strip()) and not _KEEP.sub("", _PARENS.sub("", title)).strip()


def normalize(text: str) -> str:
    """Return a comparison form without changing version semantics elsewhere.

    Traditional Chinese is folded to Simplified so a traditional-tagged track
    (李榮浩 / 麻雀 from a zh-Hant browser) compares equal to Netease's simplified
    catalogue (李荣浩), and Latin accents are folded so accented Western titles
    match their plain spelling. Both folds are applied to the track and the
    candidate alike, so they are symmetric and only ever affect this comparison
    key (never display, search queries, or version semantics).

    Deliberately free of the title-only platform cleaning: this is also the
    comparison key for artist and album, and an upload-grammar rule applied to a
    performer's name rewrites an identity rather than tidying a title. Titles
    reach here already cleaned, by split_title()."""
    value = _fold_latin_accents(unicode_normalize("NFKC", text).casefold())
    value = fold_to_simplified(value)
    stripped = _PARENS.sub("", value)
    # A title wholly inside brackets ("【七月上】", "(intro)") strips to nothing and
    # could then never match anything. Keep the bracketed text as the title in
    # that case: there it is the name, not a qualifier attached to one.
    if not _KEEP.sub("", stripped).strip():
        stripped = _BRACKET_EDGES.sub(" ", value)
    value = _FEAT_SUFFIX.sub("", stripped)
    return _KEEP.sub("", value).strip()


def split_title(title: str, artist: str = "") -> tuple[str, frozenset[str]]:
    """Split a display title into its base title and known version qualifiers."""
    value = _clean_platform_title(title, artist)
    tags: set[str] = set()
    for group in _PARENS.findall(value):
        tags.update(extract_version_tags(group))
    def remove_parenthetical(match: re.Match[str]) -> str:
        # Parentheses can be part of a token, as in the artist name (G)I-DLE.
        if match.end() < len(value) and value[match.end()].isalnum() and len(match.group(1)) <= 3:
            return match.group(0)
        return ""

    base = _PARENS.sub(remove_parenthetical, value).strip()
    # A title wholly inside brackets is the name, not a qualifier: "【七月上】"
    # would otherwise leave nothing to match on.
    if not base:
        base = _BRACKET_EDGES.sub(" ", value).strip()
    suffix = _DASH_SUFFIX.search(base)
    if suffix is not None:
        suffix_tags = extract_version_tags(suffix.group(1))
        if suffix_tags:
            tags.update(suffix_tags)
            base = base[: suffix.start()].strip()
    # Only a marker the name ends on qualifies it. Scanning the whole base title
    # tagged the name itself: "Live and Learn" came out tagged `live`, agreed with
    # "Live and Learn (Live)", and the live recording outranked the studio one the
    # user was playing. A trailing "Song Live版" is still a qualifier and still
    # conflicts with a plain candidate, which is what this loop already located.
    for pattern in VERSION_SUFFIX_PATTERNS:
        suffix_match = pattern.search(base)
        if suffix_match is not None and not base[suffix_match.end() :].strip():
            prefix = base[: suffix_match.start()].rstrip()
            if prefix:
                tags.update(extract_version_tags(base[suffix_match.start() :]))
                base = prefix
                break
    return base, frozenset(tags)




def version_labels(title: str, artist: str = "") -> tuple[str, ...]:
    """Return a title's version qualifiers as the publisher wrote them.

    split_title() reports normalized tags, which name the kind of version. A
    reader choosing between two rows needs the words the title actually carried,
    since those are what tell the rows apart. Only bracketed qualifiers are
    reported: a trailing marker with no bracket is part of the running title and
    cannot be lifted out without changing what the title says.
    """
    value = _clean_platform_title(title, artist)
    labels = (group.strip() for group in _PARENS.findall(value) if extract_version_tags(group))
    return tuple(dict.fromkeys(label for label in labels if label))


def title_without_version_labels(title: str, artist: str = "") -> str:
    """Return the title with only its version qualifiers removed.

    base_title() drops every bracketed group, which is right for matching and
    wrong for display: a production credit is not a version, so lifting one
    "(TV Size)" out beside a row must not silently take "(Prod. by ...)" with it.
    """
    value = _clean_platform_title(title, artist)

    def drop_version_group(match: re.Match[str]) -> str:
        return "" if extract_version_tags(match.group(1)) else match.group(0)

    stripped = " ".join(_PARENS.sub(drop_version_group, value).split())
    return stripped or title


def base_title(title: str) -> str:
    """Return the normalized title after removing known decoration and noise."""
    return split_title(title)[0]


def _is_title_pair(left: str, right: str) -> bool:
    left_has_cjk = bool(_CJK_ONE.search(left))
    right_has_latin = bool(re.search(r"[A-Za-z]", right))
    return left_has_cjk and right_has_latin


def _artist_from_prefix(prefix: str) -> str:
    prefix = prefix.strip(" \t\r\n-–—－")
    prefix = re.sub(r"(?i)\b(?:feat(?:uring)?|ft)\b.*$", "", prefix).strip()
    if "（" in prefix:
        if re.search(r"[一-鿿ぁ-ヿ]", prefix.split("（", 1)[1]):
            return prefix
        return prefix.split("（", 1)[0].strip()
    if "(" in prefix:
        # A single-letter parenthetical glued to the next word is part of the name,
        # not a qualifier after it: (G)I-DLE. The title cleaner already protects
        # that shape, so truncating at the bracket destroyed the same identity it
        # preserves — and it is where the performer's name starts.
        protected = re.search(r"\([A-Za-z]\)(?=[A-Za-z])", prefix)
        if protected is None:
            return prefix.split("(", 1)[0].strip()
        return prefix[protected.start() :].strip()
    # A bilingual display name usually puts the Latin alias after the real CJK name.
    cjk = re.findall(rf"[{_CJK_CLASS}]+", prefix)
    if cjk:
        return cjk[-1]
    return prefix


_LEADING_BRACKET = re.compile(r"^\s*[【『「\[]([^】』」\]]*)[】』」\]]\s*")


def recover_artist(title: str, artist: str) -> str:
    """Recover a leading title credit only when generic upload grammar supports it."""
    fallback = artist.strip()
    value = title.strip()
    if " / " in fallback:
        return fallback
    dash_parts = _TITLE_DASH.split(value, maxsplit=1)
    if len(dash_parts) == 2:
        # Strip the upload tail before deciding: "Official MV" trailing the Latin
        # half says nothing about whether the two halves are the same title, and
        # letting it veto the guard split 螺旋 - RASEN into artist and song.
        right = _TITLE_NOISE_CJK.sub(" ", _TITLE_NOISE_LATIN.sub(" ", dash_parts[1])).strip()
        # A pair is the same title twice, so the Latin half carries no CJK of its
        # own; "童話鎮 … Chen Yifa - Fairy Town" is a credit plus a translation, not
        # a pair, and treating it as one would keep the uploader as the performer.
        if right and not _CJK_ONE.search(right) and _is_title_pair(dash_parts[0], right):
            return fallback
    # Recover only a leading title credit when generic upload grammar distinguishes it from the song title.
    if not (_UPLOADER_ARTIST.search(fallback) or _TITLE_NOISE_LATIN.search(value)):
        return fallback
    prefix = dash_parts[0] if len(dash_parts) == 2 else value
    if prefix == value and not _TITLE_QUOTE.search(value) and not any(
        marker in value for marker in ("《", "『", "【", "「")
    ):
        # Nothing in the title separates a credit from the song name, so the whole
        # title is the song. Returning it as the artist replaced a real performer
        # with the title itself for every upload whose artist field happens to say
        # "records", "studio" or "channel".
        return fallback
    quoted = _TITLE_QUOTE.search(prefix)
    if quoted:
        prefix = prefix[: quoted.start()]
    # What sits before the bracket has to read like a name. A bar-separated
    # commentary lead-in ("单曲循环丨张远深情嗓好适合《达尔文》！") is a sentence about
    # the song, and taking it as the performer overwrote the reported artist for a
    # row the corpus marks as carrying no leading credit at all.
    if _TITLE_BARS.search(prefix):
        return fallback
    # A leading upload bracket goes before the markers are used as cut points:
    # "【HD】陳一發兒" would otherwise truncate at 【 and lose the performer. Only at
    # the head, so a parenthetical that is part of a name (Jam（阿敬）) survives.
    prefix = _LEADING_BRACKET.sub("", prefix, count=1).strip()
    for marker in ("《", "『", "【", "「"):
        prefix = prefix.split(marker, 1)[0]
    candidate = _artist_from_prefix(prefix)
    return candidate or fallback


_BRACKETED = re.compile(r"[【『\[（(]([^】』\]）)]*)[】』\]）)]")
# Corner/angle quotes and separators usually WRAP the title (「Lemon」《告白气球》)
# rather than junk, so they are flattened to spaces (delimiters), not removed.
_DELIMITERS = re.compile(r"[「」『』《》〈〉|/_~•・\-–—]+")
# Pure upload noise that is never part of a song name — stripped case-insensitively.
# Version words (cover/live/remix/acoustic/…) are deliberately NOT here: they change
# the recording and are handled by the version-tag logic, not thrown away.
# Latin terms use \b so they don't eat substrings of real words; the CJK terms get
# no \b — adjacent Han characters are all \w, so a word boundary never sits between
# them and "官方MV" / "完整版" would otherwise never strip out of a fused title.
_UPLOAD_NOISE_LATIN = re.compile(
    r"\b(?:officical|official|mv|m/v|hd|hq|uhd|sd|4k|8k|60fps|1080p|720p|480p|"
    r"lyrics?|lyric video|audio|music video|official (?:music )?video|official audio|"
    r"visualizer|vevo|topic|full version|hi-?res|high quality)\b",
    re.IGNORECASE,
)
_UPLOAD_NOISE_CJK = re.compile(
    r"高畫質|高画质|超高清|高清|超清|標清|完整版|完整|无损|無損|音質|音质|画质|畫質|字幕|歌词|歌詞|官方|"
    r"试听|試聽|现场|現場|直播|電視劇|电视剧|插曲|主題曲|主题曲|片頭曲|片头曲|片尾曲|主題歌|主题歌"
)
_CJK_CLASS = "㐀-鿿豈-﫿぀-ヿ가-힯"
_CJK_TOKEN = re.compile(rf"[{_CJK_CLASS}]+")
_CJK_ONE = re.compile(rf"[{_CJK_CLASS}]")
_NONWORD = re.compile(rf"[^\w{_CJK_CLASS}]+")
_LATIN_TOKEN = re.compile(r"[0-9A-Za-z][0-9A-Za-z'’&.]*")


# A bracketed guest credit is not part of the song name: "(特別演出: 派偉俊)【告白氣球
# Love Confession】" reached the catalogues carrying the guest's name and matched
# nothing, where 告白氣球 alone matches. The colon is required, so a bracketed version
# marker such as (演唱會版) — which does change which recording is meant — is never
# mistaken for a credit.
_BRACKETED_CREDIT = re.compile(r"^\s*(?:特別演出|特别演出|合唱|對唱|对唱|客串|和聲|和声)\s*[:：]")


def debracket_query_text(text: str) -> str:
    """Replace 【…】 / […] / (…) segments: drop the ones whose content is only
    upload noise (【HD】, [歌詞字幕], (Official MV)), but KEEP the content of the
    rest — some channels put the actual song title in brackets (【演員】, [ 唯一 The
    One And Only ]), and blindly stripping every bracket loses the title."""
    def keep_or_drop(match: re.Match[str]) -> str:
        inner = match.group(1)
        if match.end() < len(text) and text[match.end()].isalnum() and len(inner) <= 3:
            return match.group(0)
        if _BRACKETED_CREDIT.search(inner):
            return " "
        residue = _UPLOAD_NOISE_CJK.sub("", _UPLOAD_NOISE_LATIN.sub("", inner))
        residue = _NONWORD.sub("", residue)
        substantial = len(_CJK_ONE.findall(residue)) >= 2 or len(residue) >= 4
        return f" {inner} " if substantial else " "

    return _BRACKETED.sub(keep_or_drop, text)
_WHITESPACE = re.compile(r"\s+")


def remove_upload_noise(text: str) -> str:
    """Remove platform labels in the title grammar's required order."""
    return _UPLOAD_NOISE_LATIN.sub(" ", _UPLOAD_NOISE_CJK.sub(" ", text))


def flatten_title_delimiters(text: str) -> str:
    """Turn title separators into query whitespace without changing words."""
    return _DELIMITERS.sub(" ", text)


def cjk_runs(text: str) -> tuple[str, ...]:
    """Return CJK runs recognized by the shared title grammar."""
    return tuple(_CJK_TOKEN.findall(text))


def latin_tokens(text: str) -> tuple[str, ...]:
    """Return Latin and numeric tokens recognized by the shared title grammar."""
    return tuple(_LATIN_TOKEN.findall(text))


def normalize_query_whitespace(text: str) -> str:
    """Collapse query whitespace using the shared title boundary."""
    return _WHITESPACE.sub(" ", text)


def _quote_at_top_level(text: str) -> tuple[str, int] | None:
    for match in _TITLE_QUOTE.finditer(text):
        depth = 0
        for char in text[: match.start()]:
            if char in "([{【（":
                depth += 1
            elif char in ")]}】）" and depth:
                depth -= 1
        if depth == 0:
            content = next((group for group in match.groups() if group is not None), "").strip()
            if content:
                return content, match.end()
    return None


# A Latin run at the head of a title, ending at a separator or a CJK character:
# the romanised form of a CJK performer name that precedes it.
_LEADING_ROMANISATION = re.compile(
    r"[A-Za-z][A-Za-z.'\-]*(?:\s+[A-Za-z][A-Za-z.'\-]*){0,3}\s*"
    r"(?=[-–—－:：《〈「『【\[]|[一-鿿ぁ-ヿ])"
)


def _strip_leading_artist(value: str, artist: str) -> str:
    candidate = artist.strip()
    if not candidate or not value.casefold().startswith(candidate.casefold()):
        return value
    remainder = value[len(candidate) :]
    # A CJK credit is commonly followed straight by its romanisation with no
    # separator at all ("廖俊濤Liao juntao - 誰"), so a Latin letter is allowed there.
    immediate_latin = bool(remainder) and remainder[0].isascii() and remainder[0].isalpha()
    if remainder and not remainder[0].isspace() and remainder[0] not in "-–—－:：《〈「『【[":
        if not (immediate_latin and _CJK_ONE.search(candidate)):
            return value
    remainder = remainder.lstrip(" \t\r\n-–—－:：")
    # An upload that leads with a CJK performer usually repeats it romanised
    # ("廖俊濤Liao juntao - 誰", "美秀集團 Amazing Show－捲菸"). That Latin run is the
    # same credit, so it goes with the name rather than staying in the title.
    if _CJK_ONE.search(candidate):
        romanisation = _LEADING_ROMANISATION.match(remainder)
        if romanisation is not None:
            remainder = remainder[romanisation.end() :].lstrip(" \t\r\n-–—－:：")
    return remainder


def _segment_key(value: str) -> str:
    folded = _fold_latin_accents(unicode_normalize("NFKC", value).casefold())
    folded = fold_to_simplified(folded)
    return _KEEP.sub("", folded)


def _segment_score(segment: str, index: int, artist_key: str = "") -> tuple[int, int]:
    cleaned = _TITLE_NOISE_CJK.sub(" ", _TITLE_NOISE_LATIN.sub(" ", segment))
    score = len(_WHITESPACE.sub("", cleaned))
    score += 2 * len(_CJK_ONE.findall(cleaned))
    if len(_LATIN_TOKEN.findall(cleaned)) > 2 and _CJK_ONE.search(cleaned):
        score -= 5 * (len(_LATIN_TOKEN.findall(cleaned)) - 2)
    if _TITLE_QUOTE.search(segment):
        score += 1000
    if _TITLE_TAIL_NOISE.search(segment):
        score -= 100
    segment_key = _segment_key(segment)
    if artist_key and segment_key and segment_key in artist_key:
        # A bar-delimited segment contained in the reported artist is metadata,
        # not the title to send to lyric matching.
        score -= 10_000
    if index == 0:
        score += 4
    return score, -index


# A bracket holding nothing but a delivery-format tag is upload grammar.
_FORMAT_TAG = re.compile(r"(?i)(?:hd|hq|sd|uhd|4k|8k|2k|1080p?|720p?|mv|cc|hi-?res)")


def _clean_platform_title(title: str, artist: str = "") -> str:
    original = title.strip()
    value = unicode_normalize("NFKC", title).replace("\u3000", " ")
    segments = _TITLE_BARS.split(value)
    artist_key = _segment_key(artist)
    value = max(
        enumerate(segments),
        key=lambda item: _segment_score(item[1], item[0], artist_key),
    )[1].strip()

    quoted = _quote_at_top_level(value)
    if quoted is not None:
        content, end = quoted
        value = f"{content} {value[end:]}"
    value = _strip_leading_artist(value, artist)
    protected = re.sub(r"\([A-Za-z]\)(?=[A-Za-z])", lambda match: f"__PAREN_{match.group(0)[1]}__", value)
    value = protected
    def remove_upload_bracket(match: re.Match[str]) -> str:
        inner = match.group(1)
        # A bracket holding only a format tag (【HD】, [4K], 【1080P】) is upload
        # grammar; keeping it hid the performer credit that follows it.
        if _FORMAT_TAG.fullmatch(inner.strip()):
            return " "
        residue = _TITLE_NOISE_CJK.sub("", _TITLE_NOISE_LATIN.sub("", inner))
        residue = _NONWORD.sub("", residue)
        return " " if not residue else match.group(0)

    value = _BRACKETED.sub(remove_upload_bracket, value)
    # Again, now that a leading 【HD】-style bracket no longer hides the credit.
    value = _strip_leading_artist(value.strip(), artist)
    value = re.sub(r"__PAREN_([A-Za-z])__", r"(\1)", value)
    value = re.sub(r"[《》〈〉「」]", " ", value)
    value = _TITLE_NOISE_LATIN.sub(" ", value)
    value = _TITLE_NOISE_CJK.sub(" ", value)
    value = _WHITESPACE.sub(" ", value).strip(" \t\r\n-–—－")
    return value or original


# A lyric-video channel announces itself inside corner brackets (『動態歌詞』,
# 『歌词版』). Publisher grammar, so every ingest path needs it stripped, not only
# the MPRIS one it used to live in.
_LYRIC_VIDEO_BRACKET = re.compile(r"『[^』]*(?:動態歌詞|歌詞|歌词)[^』]*』", re.IGNORECASE)
def clean_title(title: str, artist: str = "") -> str:
    """Remove observed platform grammar while retaining recording markers."""
    cleaned = _LYRIC_VIDEO_BRACKET.sub("", _clean_platform_title(title, artist))
    return cleaned.strip() or title.strip()
