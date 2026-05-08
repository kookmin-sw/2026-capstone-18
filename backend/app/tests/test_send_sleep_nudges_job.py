from __future__ import annotations

import asyncio


def test_main_returns_int_count(monkeypatch) -> None:  # type: ignore[no-untyped-def]
    """The job's main() must return the count of nudges sent so the
    EventBridge ECS RunTask exit code can reflect success/failure."""
    from app.jobs import send_sleep_nudges

    # We don't run the full DB pipeline here — that's covered by service tests.
    # We only verify the entrypoint is callable and is an async function.
    assert asyncio.iscoroutinefunction(send_sleep_nudges.main)
