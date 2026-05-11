from __future__ import annotations

import asyncio


def test_main_is_async_coroutine_function() -> None:
    """The job's main() must be an async function returning an int count so
    the EventBridge ECS RunTask exit code can reflect success/failure."""
    from app.jobs import send_morning_tips

    assert asyncio.iscoroutinefunction(send_morning_tips.main)
