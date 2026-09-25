"""Small asyncio helpers for resources whose owner must outlive one waiter."""

from __future__ import annotations

import asyncio
from collections.abc import Coroutine
from typing import TypeVar

_Result = TypeVar("_Result")


def create_owned_task(coroutine: Coroutine[object, object, _Result], *, name: str) -> asyncio.Task[_Result]:
    """Create one owned task and close its coroutine if scheduling is rejected."""
    if not name:
        coroutine.close()
        raise ValueError("owned task name must not be empty")
    try:
        return asyncio.get_running_loop().create_task(coroutine, name=name)
    except (RuntimeError, TypeError, ValueError):
        coroutine.close()
        raise


async def wait_for_owned(future: asyncio.Future[_Result]) -> bool:
    """Wait for an owned future without cancelling it from the outside.

    Return ``True`` when the caller was cancelled while waiting. The future is
    still allowed to finish before that cancellation is restored by the owner.
    A future that is already cancelled is treated as completed control flow.
    """
    cancellation_requested = False
    while True:
        try:
            await asyncio.shield(future)
        except asyncio.CancelledError:
            if future.cancelled():
                return cancellation_requested
            cancellation_requested = True
            continue
        return cancellation_requested


__all__ = ["create_owned_task", "wait_for_owned"]
