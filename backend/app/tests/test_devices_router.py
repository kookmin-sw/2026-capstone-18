"""POST /api/v1/devices/fcm-token."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken


@pytest.mark.asyncio
async def test_register_fcm_token_creates_row(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/devices/fcm-token",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"token": "abc-123", "platform": "android"},
    )
    assert resp.status_code == 201, resp.text
    rows = (
        (await db_session.execute(select(FcmToken).where(FcmToken.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].token == "abc-123"


@pytest.mark.asyncio
async def test_register_fcm_token_is_upsert(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    for _ in range(2):
        resp = await client.post(
            "/api/v1/devices/fcm-token",
            headers=auth_headers(str(me.supabase_user_id)),
            json={"token": "abc-123", "platform": "android"},
        )
        assert resp.status_code == 201
    rows = (
        (await db_session.execute(select(FcmToken).where(FcmToken.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1


@pytest.mark.asyncio
async def test_register_fcm_token_rejects_bad_platform(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/devices/fcm-token",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"token": "abc-123", "platform": "smartwatch"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_register_fcm_token_requires_auth(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/devices/fcm-token",
        json={"token": "abc-123", "platform": "android"},
    )
    assert resp.status_code == 401
