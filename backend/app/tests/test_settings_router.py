"""GET/PATCH /api/v1/settings."""

from __future__ import annotations

from datetime import time
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user_settings import UserSettings


@pytest.mark.asyncio
async def test_get_settings_creates_default_row_for_existing_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/settings",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["notification_max_per_day"] == 5
    assert body["stress_threshold"] == 0.75
    assert body["language"] == "ko"

    row = (
        await db_session.execute(select(UserSettings).where(UserSettings.user_id == me.id))
    ).scalar_one()
    assert row.notification_max_per_day == 5


@pytest.mark.asyncio
async def test_patch_settings_updates_fields(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    db_session.add(UserSettings(user_id=me.id))
    await db_session.flush()

    resp = await client.patch(
        "/api/v1/settings",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "notification_max_per_day": 3,
            "stress_threshold": 0.6,
            "language": "en",
            "quiet_hours_start": "23:00",
            "quiet_hours_end": "07:30",
        },
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["notification_max_per_day"] == 3
    assert body["stress_threshold"] == 0.6
    assert body["language"] == "en"
    assert body["quiet_hours_start"] == "23:00:00"

    refreshed = (
        await db_session.execute(select(UserSettings).where(UserSettings.user_id == me.id))
    ).scalar_one()
    assert refreshed.notification_max_per_day == 3
    assert refreshed.quiet_hours_start == time(23, 0)


@pytest.mark.asyncio
async def test_patch_settings_rejects_out_of_range_notification_cap(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/settings",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"notification_max_per_day": 11},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_settings_rejects_out_of_range_threshold(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/settings",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"stress_threshold": 1.5},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_settings_rejects_empty_body(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/settings",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_settings_endpoints_require_auth(client: AsyncClient) -> None:
    assert (await client.get("/api/v1/settings")).status_code == 401
    assert (await client.patch("/api/v1/settings", json={"language": "en"})).status_code == 401
