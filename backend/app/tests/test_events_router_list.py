"""GET /api/v1/events with filters and pagination."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent


def _seed(db: AsyncSession, user_id: uuid.UUID, detected: datetime, **kw: Any) -> StressEvent:
    event = StressEvent(id=uuid.uuid4(), user_id=user_id, detected_at=detected, **kw)
    db.add(event)
    return event


@pytest.mark.asyncio
async def test_list_returns_only_owners_events(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    base = datetime(2026, 5, 6, 9, tzinfo=UTC)
    _seed(db_session, me.id, base)
    _seed(db_session, me.id, base + timedelta(hours=1))
    _seed(db_session, other.id, base)
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert len(body["items"]) == 2
    assert {item["user_id"] for item in body["items"]} == {str(me.id)}


@pytest.mark.asyncio
async def test_list_orders_descending_by_detected_at(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 5, 6, 9, tzinfo=UTC)
    older = _seed(db_session, me.id, base)
    newer = _seed(db_session, me.id, base + timedelta(hours=2))
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert items[0]["id"] == str(newer.id)
    assert items[1]["id"] == str(older.id)


@pytest.mark.asyncio
async def test_list_filters_by_date_range(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    _seed(db_session, me.id, datetime(2026, 5, 1, tzinfo=UTC))
    inside = _seed(db_session, me.id, datetime(2026, 5, 5, tzinfo=UTC))
    _seed(db_session, me.id, datetime(2026, 5, 10, tzinfo=UTC))
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        params={"start": "2026-05-04T00:00:00+00:00", "end": "2026-05-06T00:00:00+00:00"},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert [item["id"] for item in items] == [str(inside.id)]


@pytest.mark.asyncio
async def test_list_filters_by_logged_status(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 5, 6, 9, tzinfo=UTC)
    _seed(db_session, me.id, base, logged=False)
    logged_event = _seed(db_session, me.id, base + timedelta(hours=1), logged=True)
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        params={"logged": "true"},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert [item["id"] for item in items] == [str(logged_event.id)]


@pytest.mark.asyncio
async def test_list_filters_by_cycle_phase(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 5, 6, 9, tzinfo=UTC)
    _seed(db_session, me.id, base, cycle_phase="luteal")
    follicular = _seed(db_session, me.id, base + timedelta(hours=1), cycle_phase="follicular")
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        params={"cycle_phase": "follicular"},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert [item["id"] for item in items] == [str(follicular.id)]


@pytest.mark.asyncio
async def test_list_filters_by_chip(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 5, 6, 9, tzinfo=UTC)
    _seed(db_session, me.id, base, log_chips=["work"])
    deadline = _seed(db_session, me.id, base + timedelta(hours=1), log_chips=["work", "deadline"])
    await db_session.flush()

    resp = await client.get(
        "/api/v1/events",
        params={"chip": "deadline"},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()["items"]
    assert [item["id"] for item in items] == [str(deadline.id)]


@pytest.mark.asyncio
async def test_list_paginates_with_cursor(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 5, 6, 0, tzinfo=UTC)
    for hour in range(5):
        _seed(db_session, me.id, base + timedelta(hours=hour))
    await db_session.flush()

    resp1 = await client.get(
        "/api/v1/events",
        params={"limit": 2},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    body1 = resp1.json()
    assert len(body1["items"]) == 2
    assert body1["next_cursor"] is not None

    resp2 = await client.get(
        "/api/v1/events",
        params={"limit": 2, "cursor": body1["next_cursor"]},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    body2 = resp2.json()
    assert len(body2["items"]) == 2
    assert body2["next_cursor"] is not None

    resp3 = await client.get(
        "/api/v1/events",
        params={"limit": 2, "cursor": body2["next_cursor"]},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    body3 = resp3.json()
    assert len(body3["items"]) == 1
    assert body3["next_cursor"] is None


@pytest.mark.asyncio
async def test_list_rejects_inverted_date_range(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/events",
        params={
            "start": "2026-05-08T00:00:00+00:00",
            "end": "2026-05-01T00:00:00+00:00",
        },
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_list_rejects_garbage_cursor(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/events",
        params={"cursor": "not-a-real-cursor"},
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422
