"""CRUD tests for /api/v1/categories."""

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


@pytest.mark.asyncio
async def test_patch_renames_category(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "Werk", "color": "#111111"},
        )
    ).json()

    resp = await client.patch(
        f"/api/v1/categories/{created['id']}",
        headers=headers,
        json={"name": "Work Pressure", "color": "#7C3AED"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["name"] == "Work Pressure"
    assert body["color"] == "#7C3AED"

    refreshed = (
        await db_session.execute(
            select(TriggerCategory).where(TriggerCategory.id == uuid.UUID(created["id"]))
        )
    ).scalar_one()
    assert refreshed.name == "Work Pressure"


@pytest.mark.asyncio
async def test_patch_rejects_empty_body(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "X", "color": "#111111"},
        )
    ).json()

    resp = await client.patch(
        f"/api/v1/categories/{created['id']}",
        headers=headers,
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_404_for_other_user_category(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    created = (
        await client.post(
            "/api/v1/categories",
            headers=auth_headers(str(other.supabase_user_id)),
            json={"name": "Theirs", "color": "#222222"},
        )
    ).json()

    resp = await client.patch(
        f"/api/v1/categories/{created['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"name": "Mine"},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_delete_soft_archives_and_clears_events(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    from datetime import UTC, datetime

    from app.models.stress_event import StressEvent

    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "Temp", "color": "#222222"},
        )
    ).json()
    cat_id = uuid.UUID(created["id"])

    event = StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=datetime(2026, 5, 6, 9, tzinfo=UTC),
        category_id=cat_id,
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.delete(
        f"/api/v1/categories/{created['id']}",
        headers=headers,
    )
    assert resp.status_code == 204

    refreshed = (
        await db_session.execute(select(TriggerCategory).where(TriggerCategory.id == cat_id))
    ).scalar_one()
    assert refreshed.archived_at is not None

    await db_session.refresh(event)
    assert event.category_id is None

    list_resp = await client.get("/api/v1/categories", headers=headers)
    assert list_resp.json()["items"] == []


@pytest.mark.asyncio
async def test_delete_404_for_other_user_category(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    created = (
        await client.post(
            "/api/v1/categories",
            headers=auth_headers(str(other.supabase_user_id)),
            json={"name": "Theirs", "color": "#222222"},
        )
    ).json()

    resp = await client.delete(
        f"/api/v1/categories/{created['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_can_recreate_after_archive(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    first = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "Reborn", "color": "#111111"},
        )
    ).json()
    await client.delete(f"/api/v1/categories/{first['id']}", headers=headers)

    again = await client.post(
        "/api/v1/categories",
        headers=headers,
        json={"name": "Reborn", "color": "#222222"},
    )
    assert again.status_code == 201
