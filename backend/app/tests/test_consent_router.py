"""GET/PATCH /api/v1/consent."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_settings import UserSettings


@pytest.mark.asyncio
async def test_get_consent_returns_initial_state(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["consent_raw_biosignals"] is False
    assert body["consent_revoked_at"] is None
    assert body["consent_audit_logging"] is True


@pytest.mark.asyncio
async def test_patch_consent_grants_raw_biosignals(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"consent_raw_biosignals": True},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["consent_raw_biosignals"] is True
    assert body["consent_revoked_at"] is None

    refreshed = (await db_session.execute(select(User).where(User.id == me.id))).scalar_one()
    assert refreshed.consent_raw_biosignals is True
    assert refreshed.consent_revoked_at is None


@pytest.mark.asyncio
async def test_patch_consent_revoke_sets_timestamp(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(consent_raw_biosignals=True)
    before = datetime.now(tz=UTC)

    resp = await client.patch(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"consent_raw_biosignals": False},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["consent_raw_biosignals"] is False
    assert body["consent_revoked_at"] is not None

    refreshed = (await db_session.execute(select(User).where(User.id == me.id))).scalar_one()
    assert refreshed.consent_raw_biosignals is False
    assert refreshed.consent_revoked_at is not None
    assert abs((refreshed.consent_revoked_at - before).total_seconds()) < 60


@pytest.mark.asyncio
async def test_patch_consent_re_grant_clears_revocation(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(
        consent_raw_biosignals=False,
        consent_revoked_at=datetime.now(tz=UTC) - timedelta(days=1),
    )
    resp = await client.patch(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"consent_raw_biosignals": True},
    )
    assert resp.status_code == 200
    refreshed = (await db_session.execute(select(User).where(User.id == me.id))).scalar_one()
    assert refreshed.consent_raw_biosignals is True
    assert refreshed.consent_revoked_at is None


@pytest.mark.asyncio
async def test_patch_consent_audit_logging_toggle(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"consent_audit_logging": False},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["consent_audit_logging"] is False

    settings_row = (
        await db_session.execute(select(UserSettings).where(UserSettings.user_id == me.id))
    ).scalar_one()
    assert settings_row.consent_audit_logging is False


@pytest.mark.asyncio
async def test_patch_consent_rejects_empty_body(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/consent",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_consent_endpoints_require_auth(client: AsyncClient) -> None:
    assert (await client.get("/api/v1/consent")).status_code == 401
    assert (
        await client.patch("/api/v1/consent", json={"consent_raw_biosignals": True})
    ).status_code == 401
