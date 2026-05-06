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
