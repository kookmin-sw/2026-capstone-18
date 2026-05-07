"""POST/GET tests for /api/v1/categories."""

from __future__ import annotations

import uuid
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.trigger_category import TriggerCategory


@pytest.mark.asyncio
async def test_post_creates_category(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/categories",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"name": "Work Pressure", "color": "#7C3AED"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["name"] == "Work Pressure"
    assert body["color"] == "#7C3AED"
    assert body["sort_order"] == 0
    assert body["archived_at"] is None
    assert body["event_count"] == 0

    row = (
        await db_session.execute(
            select(TriggerCategory).where(TriggerCategory.id == uuid.UUID(body["id"]))
        )
    ).scalar_one()
    assert row.user_id == me.id


@pytest.mark.asyncio
async def test_post_rejects_duplicate_name_for_same_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    first = await client.post(
        "/api/v1/categories",
        headers=headers,
        json={"name": "Work", "color": "#7C3AED"},
    )
    assert first.status_code == 201

    dupe = await client.post(
        "/api/v1/categories",
        headers=headers,
        json={"name": "work", "color": "#FF0000"},  # different case, same active name
    )
    assert dupe.status_code == 409


@pytest.mark.asyncio
async def test_get_list_returns_only_caller_categories(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    await client.post(
        "/api/v1/categories",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"name": "Mine", "color": "#111111"},
    )
    await client.post(
        "/api/v1/categories",
        headers=auth_headers(str(other.supabase_user_id)),
        json={"name": "Theirs", "color": "#222222"},
    )

    resp = await client.get(
        "/api/v1/categories",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert len(items) == 1
    assert items[0]["name"] == "Mine"
