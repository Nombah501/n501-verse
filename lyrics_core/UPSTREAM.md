# Lyrics Core provenance

The Lyrics Core is derived from [Kotonoha](https://github.com/locez/kotonoha)
and is owned and maintained here (hard fork, no upstream tracking; see
`docs/adr/0006-own-lyrics-core.md`). Kotonoha's Python sources are MIT
licensed; the notice is kept in `LICENSE` next to this file.

## Upstream Base

- Repository: https://github.com/locez/kotonoha
- Commit: `175cfcc04ffb67fbbba26c76437275083090233a` (`src/kotonoha/`)
- Package it matched: Arch `kotonoha-git 0.2.3.r241.g175cfcc-1`

To port an upstream fix, diff the upstream change against this commit and
apply it by hand.

## Copied files

These 31 modules are the closure `bin/karaoke-lyrics` reaches. At copy time
each was sha256-identical in three places: upstream git at the Upstream Base,
the installed `kotonoha-git` package, and this directory.

```
__init__.py  async_task.py  file_access.py
display/offsets.py  playback/models.py  state/track_offset_store.py
lyrics/__init__.py  lyrics/adapter.py  lyrics/artifact.py
lyrics/artist_grammar.py  lyrics/hanzi_fold.py  lyrics/hint.py  lyrics/http.py
lyrics/krc_parser.py  lyrics/kugou.py  lyrics/local.py  lyrics/lrc_parser.py
lyrics/lrclib.py  lyrics/match.py  lyrics/models.py  lyrics/netease.py
lyrics/payload.py  lyrics/player_title_grammar.py  lyrics/search_policy.py
lyrics/title_grammar.py  lyrics/title_queries.py  lyrics/translation.py
lyrics/version_grammar.py  lyrics/yrc_parser.py
lyrics/cache/models.py  lyrics/cache/storage.py
```

## Deviations from upstream

- `__init__.py`: `__version__` is `"0.2.3"` instead of upstream's stale
  `"0.1.0"`, so the reported version matches what the helper reported from
  package metadata before the fork.
- The `__init__.py` files of `display/`, `playback/`, `state/`, and
  `lyrics/cache/` are not copied. Upstream's versions eagerly import modules
  the plugin never uses (`async_worker`, `display.layout`, `display.models`,
  and more). Without them these directories are implicit namespace subpackages
  of the regular `lyrics_core` package, so only modules that are actually
  imported get loaded. `async_task.py` is the only small helper module kept:
  `lyrics/lrclib.py` uses its `create_owned_task` for the concurrent
  exact-get and search requests. Every copied module is reachable from the
  helper.

- `lyrics/http.py` replaces the upstream third-party async HTTP client with
  cookie-free stdlib `urllib.request` on daemon workers so a cancelled socket
  operation cannot delay helper shutdown. Bounded reads, compression, total
  provider deadlines, and the `LyricsSession` seam remain. `LyricsTimeout`
  keeps only the total budget; a separate connection budget would also limit
  slow response headers. The opener ignores proxy environment variables as
  upstream did. Unlike upstream, it does not follow 307/308 POST redirects;
  no current provider sends POST requests.

- `lyrics/cache/storage.py` and `state/track_offset_store.py` use private
  `n501.karaoke` XDG stores instead of Kotonoha's stores.
- `kotonoha_import.py` copies compatible manual cache entries and Timing
  Offsets from Kotonoha's read-only files once, when each plugin store is new.
  For WAL databases without sidecars, immutable read-only mode prevents SQLite
  from creating files in Kotonoha's directory. With existing WAL sidecars,
  normal read-only mode preserves the database and WAL bytes and directory
  listing; SQLite may update the `-shm` shared-memory reader protocol file.
- `lyrics/lrclib.py` identifies this plugin in its `User-Agent`
  (`n501.karaoke/<version> (repo URL)`) instead of upstream's Kotonoha
  string, as LRCLIB asks clients to identify themselves.

## Tests

The upstream tests for the copied modules are ported to `unittest` in
`tests/test_lyrics_core.py` and `tests/test_lyrics_match.py`:
`test_lyrics_krc.py`, `test_lyric_formats.py`, `test_track_offsets.py`
(without the Qt app service), `test_lyrics_cache.py`, `test_lyrics_local.py`,
`test_lyrics_hint.py`, `test_titles.py`, the `parse_payload` cases of
`test_lyrics_providers.py`, and the matching/title/similarity cases of
`test_lyrics.py`. A fixed-vector test pins the Timing Offset key digest to
the value the Upstream Base produces.

HTTP requests and provider fetches are covered against a local server in
`tests/test_lyrics_transport.py`, replacing the upstream HTTP-session tests.

Not ported:

- Every other upstream test file (Qt UI, MPRIS/D-Bus, display engine, config,
  controller, Cider, QQ Music, resolver/workflow/search window, architecture,
  behaviour corpus). Their subjects were not copied.
