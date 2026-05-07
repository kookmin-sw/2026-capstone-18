"""POST/PATCH stress events with category_id."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_post_event_with_valid_category(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    cat = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "Work", "color": "#7C3AED"},
        )
    ).json()

    resp = await client.post(
        "/api/v1/events",
        headers=headers,
        json={
            "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["category_id"] == cat["id"]

    refreshed = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == uuid.UUID(body["id"])))
    ).scalar_one()
    assert str(refreshed.category_id) == cat["id"]


@pytest.mark.asyncio
async def test_post_event_rejects_other_user_category(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    cat = (
        await client.post(
            "/api/v1/categories",
            headers=auth_headers(str(other.supabase_user_id)),
            json={"name": "Theirs", "color": "#111111"},
        )
    ).json()

    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
            "category_id": cat["id"],
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_event_changes_category(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    cat_a = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "A", "color": "#111111"},
        )
    ).json()
    cat_b = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "B", "color": "#222222"},
        )
    ).json()

    event = StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=datetime(2026, 5, 6, 9, tzinfo=UTC),
        category_id=uuid.UUID(cat_a["id"]),
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=headers,
        json={"category_id": cat_b["id"]},
    )
    assert resp.status_code == 200
    assert resp.json()["category_id"] == cat_b["id"]


@pytest.mark.asyncio
async def test_patch_event_clears_category_with_explicit_null(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    cat = (
        await client.post(
            "/api/v1/categories",
            headers=headers,
            json={"name": "X", "color": "#111111"},
        )
    ).json()

    event = StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=datetime(2026, 5, 6, 9, tzinfo=UTC),
        category_id=uuid.UUID(cat["id"]),
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=headers,
        json={"category_id": None, "logged": True},
    )
    assert resp.status_code == 200
    assert resp.json()["category_id"] is None
