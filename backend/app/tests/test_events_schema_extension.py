"""Round-trip tests for Plan A schema additions."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent


def test_model_has_new_columns() -> None:
    """ORM-level smoke check: column attributes exist."""
    assert hasattr(StressEvent, "user_stress_level")
    assert hasattr(StressEvent, "mood_chips")


def test_user_model_has_display_name() -> None:
    from app.models.user import User

    assert hasattr(User, "display_name")


def test_create_schema_validates_stress_level_range() -> None:
    from app.schemas.events import StressEventCreate

    base = {
        "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
    }
    # Lower bound
    StressEventCreate.model_validate({**base, "user_stress_level": 0})
    # Upper bound
    StressEventCreate.model_validate({**base, "user_stress_level": 100})

    with pytest.raises(ValidationError):
        StressEventCreate.model_validate({**base, "user_stress_level": -1})
    with pytest.raises(ValidationError):
        StressEventCreate.model_validate({**base, "user_stress_level": 101})


def test_update_schema_accepts_partial_mood_chips() -> None:
    from app.schemas.events import StressEventUpdate

    upd = StressEventUpdate.model_validate({"mood_chips": ["anxious", "irritated"]})
    assert upd.mood_chips == ["anxious", "irritated"]
    assert upd.is_empty() is False


@pytest.mark.asyncio
async def test_post_event_persists_user_stress_level_and_mood_chips(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
            "user_stress_level": 62,
            "mood_chips": ["anxious", "overwhelmed"],
            "logged": True,
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_stress_level"] == 62
    assert body["mood_chips"] == ["anxious", "overwhelmed"]

    refreshed = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == uuid.UUID(body["id"])))
    ).scalar_one()
    assert refreshed.user_stress_level == 62
    assert refreshed.mood_chips == ["anxious", "overwhelmed"]


@pytest.mark.asyncio
async def test_patch_event_updates_mood_chips_and_user_stress(
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
        json={"user_stress_level": 75, "mood_chips": ["sad"]},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["user_stress_level"] == 75
    assert body["mood_chips"] == ["sad"]

    refreshed = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == event.id))
    ).scalar_one()
    assert refreshed.user_stress_level == 75
    assert refreshed.mood_chips == ["sad"]


@pytest.mark.asyncio
async def test_post_event_rejects_out_of_range_stress_level(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
            "user_stress_level": 150,
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_event_persists_user_stress_level_zero_boundary(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
            "user_stress_level": 0,
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_stress_level"] == 0

    refreshed = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == uuid.UUID(body["id"])))
    ).scalar_one()
    assert refreshed.user_stress_level == 0


@pytest.mark.asyncio
async def test_patch_partial_user_stress_does_not_clear_mood_chips(
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
        mood_chips=["anxious"],
        user_stress_level=40,
    )
    db_session.add(event)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/events/{event.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"user_stress_level": 80},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["user_stress_level"] == 80
    assert body["mood_chips"] == ["anxious"]

    await db_session.refresh(event)
    assert event.user_stress_level == 80
    assert event.mood_chips == ["anxious"]
