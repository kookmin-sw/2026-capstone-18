"""Lifespan integration: _purge_loop runs the deletion services on a timer."""

from __future__ import annotations

import asyncio

import pytest


@pytest.mark.asyncio
async def test_purge_loop_invokes_both_services(monkeypatch: pytest.MonkeyPatch) -> None:
    """Single iteration of _purge_loop should call both purge functions and commit."""
    from app import main as main_module

    calls: list[str] = []

    async def fake_accounts(db: object, *, grace_window_days: int) -> int:
        calls.append(f"accounts:{grace_window_days}")
        return 0

    async def fake_biosignals(db: object) -> int:
        calls.append("biosignals")
        return 0

    monkeypatch.setattr(main_module, "purge_expired_accounts", fake_accounts)
    monkeypatch.setattr(main_module, "purge_revoked_biosignals", fake_biosignals)

    sleeps: list[float] = []

    async def fake_sleep(delay: float) -> None:
        sleeps.append(delay)
        raise asyncio.CancelledError

    monkeypatch.setattr(asyncio, "sleep", fake_sleep)

    with pytest.raises(asyncio.CancelledError):
        await main_module._purge_loop()

    assert "accounts:30" in calls
    assert "biosignals" in calls
    assert sleeps == [3600]


@pytest.mark.asyncio
async def test_purge_loop_swallows_iteration_error(monkeypatch: pytest.MonkeyPatch) -> None:
    """A failing iteration logs but does not crash the loop."""
    from app import main as main_module

    async def boom(*args: object, **kwargs: object) -> int:
        raise RuntimeError("db is down")

    monkeypatch.setattr(main_module, "purge_expired_accounts", boom)
    monkeypatch.setattr(main_module, "purge_revoked_biosignals", boom)

    async def fake_sleep(_: float) -> None:
        raise asyncio.CancelledError

    monkeypatch.setattr(asyncio, "sleep", fake_sleep)

    # Loop must reach the sleep (i.e. not propagate the RuntimeError).
    with pytest.raises(asyncio.CancelledError):
        await main_module._purge_loop()
