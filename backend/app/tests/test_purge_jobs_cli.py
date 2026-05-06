"""Smoke tests for the CLI wrappers around app.services.deletion."""

from __future__ import annotations

import pytest


@pytest.mark.asyncio
async def test_purge_accounts_main_invokes_service(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.jobs import purge_accounts

    captured: dict[str, object] = {}

    async def fake_purge(db: object, *, grace_window_days: int) -> int:
        captured["grace_window_days"] = grace_window_days
        return 7

    monkeypatch.setattr(purge_accounts, "purge_expired_accounts", fake_purge)

    deleted = await purge_accounts.main(grace_window_days=42)

    assert deleted == 7
    assert captured == {"grace_window_days": 42}


@pytest.mark.asyncio
async def test_purge_biosignals_main_invokes_service(monkeypatch: pytest.MonkeyPatch) -> None:
    from app.jobs import purge_biosignals

    captured: dict[str, object] = {}

    async def fake_purge(db: object) -> int:
        captured["called"] = True
        return 3

    monkeypatch.setattr(purge_biosignals, "purge_revoked_biosignals", fake_purge)

    deleted = await purge_biosignals.main()

    assert deleted == 3
    assert captured == {"called": True}


def test_purge_accounts_cli_invokes_main(monkeypatch: pytest.MonkeyPatch) -> None:
    """`_cli()` parses argv, configures logging, and dispatches to main."""
    import asyncio

    from app.jobs import purge_accounts

    captured: dict[str, object] = {}

    def fake_run(coro: object) -> None:
        # Drain the coroutine so Python doesn't warn about unawaited.
        import inspect

        if inspect.iscoroutine(coro):
            coro.close()
        captured["ran"] = True

    def fake_configure(level: str) -> None:
        captured["log_level"] = level

    monkeypatch.setattr("sys.argv", ["purge_accounts", "--grace-window-days", "0"])
    monkeypatch.setattr(asyncio, "run", fake_run)
    monkeypatch.setattr(purge_accounts, "configure_logging", fake_configure)

    purge_accounts._cli()

    assert captured["ran"] is True
    assert "log_level" in captured


def test_purge_biosignals_cli_invokes_main(monkeypatch: pytest.MonkeyPatch) -> None:
    """`_cli()` parses argv, configures logging, and dispatches to main."""
    import asyncio

    from app.jobs import purge_biosignals

    captured: dict[str, object] = {}

    def fake_run(coro: object) -> None:
        import inspect

        if inspect.iscoroutine(coro):
            coro.close()
        captured["ran"] = True

    def fake_configure(level: str) -> None:
        captured["log_level"] = level

    monkeypatch.setattr("sys.argv", ["purge_biosignals"])
    monkeypatch.setattr(asyncio, "run", fake_run)
    monkeypatch.setattr(purge_biosignals, "configure_logging", fake_configure)

    purge_biosignals._cli()

    assert captured["ran"] is True
    assert "log_level" in captured
