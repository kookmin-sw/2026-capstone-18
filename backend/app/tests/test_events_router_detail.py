"""GET /api/v1/events/{id}."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_get_event_returns_owners_event(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    event = StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=datetime(2026, 5, 6, 9, tzinfo=UTC),
        log_chips=["work"],
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.get(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["id"] == str(event.id)
    assert body["log_chips"] == ["work"]


@pytest.mark.asyncio
async def test_get_event_404s_for_other_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    event = StressEvent(
        id=uuid.uuid4(),
        user_id=other.id,
        detected_at=datetime(2026, 5, 6, 9, tzinfo=UTC),
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.get(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_event_404s_for_unknown_id(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        f"/api/v1/events/{uuid.uuid4()}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_event_requires_auth(client: AsyncClient) -> None:
    resp = await client.get(f"/api/v1/events/{uuid.uuid4()}")
    assert resp.status_code == 401
