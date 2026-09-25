"""Small HTTP capability shared by lyric provider implementations."""

from __future__ import annotations

import asyncio
import http.client
import json as json_module
import socket
import threading
import zlib
from collections.abc import Mapping
from contextlib import AbstractAsyncContextManager
from dataclasses import dataclass
from types import TracebackType
from typing import Callable, Protocol, TypeVar
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit, urlunsplit
from urllib.request import ProxyHandler, Request, build_opener


class LyricsResponseContent(Protocol):
    """Bounded response body reader needed by lyric payload parsers."""

    async def read(self, size: int = -1, /) -> bytes: ...


class LyricsHttpError(RuntimeError):
    """A transport-level HTTP failure normalized for lyric feature callers."""


class LyricsResponse(Protocol):
    """The response facts consumed by provider boundary helpers."""

    @property
    def status(self) -> int: ...

    @property
    def content(self) -> LyricsResponseContent: ...

    def raise_for_status(self) -> None: ...

    async def __aenter__(self) -> LyricsResponse: ...

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
        /,
    ) -> None: ...


class LyricsSession(Protocol):
    """HTTP capability exposed to lyric sources instead of a concrete client."""

    def get(
        self,
        url: str,
        *,
        params: Mapping[str, str] | None = None,
        headers: Mapping[str, str] | None = None,
        timeout: object | None = None,
    ) -> AbstractAsyncContextManager[LyricsResponse]: ...

    def post(
        self,
        url: str,
        *,
        json: object | None = None,
        params: Mapping[str, str] | None = None,
        headers: Mapping[str, str] | None = None,
        timeout: object | None = None,
    ) -> AbstractAsyncContextManager[LyricsResponse]: ...

    async def close(self) -> None: ...


T = TypeVar("T")


async def _run_blocking(func: Callable[[], T], abandon: Callable[[T], None] | None = None) -> T:
    """Never join a cancelled socket operation during asyncio.run shutdown."""
    loop = asyncio.get_running_loop()
    future: asyncio.Future[T] = loop.create_future()

    def deliver(result: T | None, error: BaseException | None) -> None:
        if future.done():
            if error is None and abandon is not None:
                threading.Thread(target=abandon, args=(result,), daemon=True).start()
        elif error is not None:
            future.set_exception(error)
        else:
            future.set_result(result)  # type: ignore[arg-type]

    def worker() -> None:
        try:
            result = func()
        except BaseException as exc:
            try:
                loop.call_soon_threadsafe(deliver, None, exc)
            except RuntimeError:
                pass  # The loop was closed after cancelling this request.
        else:
            try:
                loop.call_soon_threadsafe(deliver, result, None)
            except RuntimeError:
                if abandon is not None:
                    abandon(result)

    threading.Thread(target=worker, daemon=True).start()
    return await future


def _interrupt(response: http.client.HTTPResponse) -> None:
    try:
        response.fp.raw._sock.shutdown(socket.SHUT_RDWR)
    except (AttributeError, OSError):
        pass


@dataclass(frozen=True)
class LyricsTimeout:
    total: float


class UrllibLyricsSession:
    """Run blocking stdlib requests off the event loop without retaining cookies."""

    def __init__(self, timeout: LyricsTimeout = LyricsTimeout(20.0)) -> None:
        self._timeout = timeout
        self._opener = build_opener(ProxyHandler({}))
        self._responses: set[http.client.HTTPResponse] = set()

    def get(
        self,
        url: str,
        *,
        params: Mapping[str, str] | None = None,
        headers: Mapping[str, str] | None = None,
        timeout: object | None = None,
    ) -> AbstractAsyncContextManager[LyricsResponse]:
        return self._request(url, "GET", None, params, headers, timeout)

    def post(
        self,
        url: str,
        *,
        json: object | None = None,
        params: Mapping[str, str] | None = None,
        headers: Mapping[str, str] | None = None,
        timeout: object | None = None,
    ) -> AbstractAsyncContextManager[LyricsResponse]:
        request_headers = dict(headers or {})
        body = json_module.dumps(json).encode("utf-8") if json is not None else None
        if body is not None and not any(key.lower() == "content-type" for key in request_headers):
            request_headers["Content-Type"] = "application/json"
        return self._request(url, "POST", body, params, request_headers, timeout)

    def _request(
        self,
        url: str,
        method: str,
        body: bytes | None,
        params: Mapping[str, str] | None,
        headers: Mapping[str, str] | None,
        timeout: object | None,
    ) -> _UrllibResponse:
        budget = self._timeout if timeout is None else timeout
        if isinstance(budget, (int, float)):
            budget = LyricsTimeout(float(budget))
        if not isinstance(budget, LyricsTimeout):
            raise TypeError("unsupported lyric HTTP timeout")
        if params:
            parts = urlsplit(url)
            query = "&".join(filter(None, (parts.query, urlencode(params))))
            url = urlunsplit((parts.scheme, parts.netloc, parts.path, query, parts.fragment))
        request_headers = dict(headers or {})
        if not any(key.lower() == "accept-encoding" for key in request_headers):
            request_headers["Accept-Encoding"] = "gzip, deflate"
        req = Request(url, data=body, headers=request_headers, method=method)
        return _UrllibResponse(self, req, budget)

    async def close(self) -> None:
        responses = tuple(self._responses)
        self._responses.clear()
        for response in responses:
            _interrupt(response)
        await asyncio.gather(*(_run_blocking(response.close) for response in responses))


class _UrllibContent:
    def __init__(self, response: http.client.HTTPResponse, deadline: float) -> None:
        self._response = response
        self._deadline = deadline
        self._wire_remaining = response.length
        encoding = response.headers.get("Content-Encoding", "").lower()
        self._decoder = zlib.decompressobj(47) if encoding in ("gzip", "deflate") else None
        self._raw_fallback = encoding == "deflate"
        self._pending = b""
        self._eof = False

    async def _read_wire(self, size: int) -> bytes:
        remaining = self._deadline - asyncio.get_running_loop().time()
        if remaining <= 0:
            raise TimeoutError("lyric HTTP request timed out")

        def read() -> bytes:
            try:
                sock = self._response.fp.raw._sock
                sock.settimeout(min(sock.gettimeout() or remaining, remaining))
            except AttributeError:
                pass
            return self._response.read(size)

        data = await asyncio.wait_for(_run_blocking(read), remaining)
        if self._wire_remaining is not None:
            self._wire_remaining -= len(data)
            if not data and self._wire_remaining > 0:
                raise LyricsHttpError("lyric HTTP response ended before Content-Length")
        return data

    async def read(self, size: int = -1, /) -> bytes:
        if size == 0:
            return b""
        try:
            if self._decoder is None:
                return await self._read_wire(size)
            output = bytearray()
            while size < 0 or len(output) < size:
                if not self._pending and not self._eof:
                    self._pending = await self._read_wire(8192)
                    if not self._pending:
                        self._eof = True
                        if not self._decoder.eof:
                            raise LyricsHttpError("lyric HTTP compressed response is incomplete")
                if not self._pending:
                    output.extend(self._decoder.flush())
                    break
                try:
                    chunk = self._decoder.decompress(
                        self._pending, 8192 if size < 0 else size - len(output)
                    )
                except zlib.error:
                    if not self._raw_fallback:
                        raise
                    self._decoder = zlib.decompressobj(-zlib.MAX_WBITS)
                    self._raw_fallback = False
                    chunk = self._decoder.decompress(
                        self._pending, 8192 if size < 0 else size - len(output)
                    )
                self._raw_fallback = False
                self._pending = self._decoder.unconsumed_tail
                output.extend(chunk)
                if self._decoder.eof:
                    if self._wire_remaining is not None and self._wire_remaining > 0:
                        raise LyricsHttpError("lyric HTTP response ended before Content-Length")
                    self._pending = b""
                    self._eof = True
                if self._eof and not self._pending:
                    output.extend(self._decoder.flush())
                    break
            return bytes(output)
        except TimeoutError:
            raise
        except (URLError, OSError, http.client.HTTPException, zlib.error) as exc:
            raise LyricsHttpError("lyric HTTP response read failed") from exc


class _UrllibResponse:
    def __init__(self, session: UrllibLyricsSession, request: Request, timeout: LyricsTimeout) -> None:
        self._session = session
        self._request = request
        self._timeout = timeout
        self._entered: http.client.HTTPResponse | None = None
        self._content: _UrllibContent | None = None

    @property
    def status(self) -> int:
        if self._entered is None:
            raise RuntimeError("lyric HTTP response was read before entering its context")
        return self._entered.status

    @property
    def content(self) -> LyricsResponseContent:
        if self._content is None:
            raise RuntimeError("lyric HTTP response was read before entering its context")
        return self._content

    def raise_for_status(self) -> None:
        if self.status >= 400:
            raise LyricsHttpError(f"lyric HTTP response returned status {self.status}")

    async def __aenter__(self) -> LyricsResponse:
        budget = self._timeout.total
        loop = asyncio.get_running_loop()
        deadline = loop.time() + budget
        socket_timeout = budget

        def open_request() -> http.client.HTTPResponse:
            try:
                return self._session._opener.open(self._request, timeout=socket_timeout)
            except HTTPError as exc:
                return exc

        try:
            response = await asyncio.wait_for(
                _run_blocking(open_request, abandon=lambda response: response.close()),
                max(0, deadline - loop.time()),
            )
        except TimeoutError:
            raise
        except (URLError, OSError, http.client.HTTPException) as exc:
            raise LyricsHttpError("lyric HTTP request could not be opened") from exc
        self._entered = response
        self._session._responses.add(response)
        self._content = _UrllibContent(response, deadline)
        return self

    async def __aexit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
        /,
    ) -> None:
        response = self._entered
        if response is not None:
            self._session._responses.discard(response)
            _interrupt(response)
            threading.Thread(target=response.close, daemon=True).start()


def new_lyrics_session() -> UrllibLyricsSession:
    """Create the bounded, cookie-isolated session shared by lyric workflows."""
    return UrllibLyricsSession()


__all__ = [
    "LyricsHttpError",
    "LyricsResponse",
    "LyricsResponseContent",
    "LyricsSession",
    "LyricsTimeout",
    "UrllibLyricsSession",
    "new_lyrics_session",
]
