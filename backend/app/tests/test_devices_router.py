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


@pytest.mark.asyncio
async def test_delete_fcm_token_removes_row(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """DELETE removes the matching row for the current user."""
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))
    await client.post(
        "/api/v1/devices/fcm-token",
        headers=headers,
        json={"token": "fake-token-1", "platform": "android"},
    )

    resp = await client.request(
        "DELETE",
        "/api/v1/devices/fcm-token",
        headers=headers,
        json={"token": "fake-token-1"},
    )

    assert resp.status_code == 204, resp.text
    rows = (
        (
            await db_session.execute(
                select(FcmToken).where(
                    FcmToken.user_id == me.id,
                    FcmToken.token == "fake-token-1",
                )
            )
        )
        .scalars()
        .all()
    )
    assert rows == []


@pytest.mark.asyncio
async def test_delete_fcm_token_is_idempotent(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """Deleting a token that was never registered still returns 204."""
    me = await make_user()
    resp = await client.request(
        "DELETE",
        "/api/v1/devices/fcm-token",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"token": "never-registered"},
    )

    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_delete_fcm_token_only_affects_current_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """Deleting must not touch another user's row even with the same token string."""
    other = await make_user()
    other_row = FcmToken(user_id=other.id, token="shared-token", platform="android")
    db_session.add(other_row)
    await db_session.flush()
    other_user_id = other.id

    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))
    await client.post(
        "/api/v1/devices/fcm-token",
        headers=headers,
        json={"token": "shared-token", "platform": "android"},
    )

    resp = await client.request(
        "DELETE",
        "/api/v1/devices/fcm-token",
        headers=headers,
        json={"token": "shared-token"},
    )

    assert resp.status_code == 204
    refreshed = await db_session.get(FcmToken, (other_user_id, "shared-token"))
    assert refreshed is not None


@pytest.mark.asyncio
async def test_delete_fcm_token_requires_auth(client: AsyncClient) -> None:
    resp = await client.request(
        "DELETE",
        "/api/v1/devices/fcm-token",
        json={"token": "abc-123"},
    )
    assert resp.status_code == 401
