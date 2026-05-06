"""PATCH /api/v1/events/{id}."""

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
async def test_patch_logs_event_after_the_fact(
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
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"logged": True, "log_chips": ["meeting"], "log_text": "stand-up ran long"},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["logged"] is True
    assert body["log_chips"] == ["meeting"]

    refreshed = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == event.id))
    ).scalar_one()
    assert refreshed.log_text == "stand-up ran long"


@pytest.mark.asyncio
async def test_patch_rejects_empty_body(
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
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_404s_for_other_user(
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

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"logged": True},
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_patch_partial_does_not_clear_other_fields(
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
        log_text="initial note",
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"logged": True},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["log_chips"] == ["work"]
    assert body["log_text"] == "initial note"
    assert body["logged"] is True
