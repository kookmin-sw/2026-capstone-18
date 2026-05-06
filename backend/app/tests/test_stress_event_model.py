"""StressEvent ORM model basics."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent
from app.models.user import User


@pytest.mark.asyncio
async def test_stress_event_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    detected = datetime(2026, 5, 6, 12, 0, tzinfo=UTC)
    event = StressEvent(
        user_id=user.id,
        detected_at=detected,
        model_confidence=0.91,
        cycle_phase="luteal",
        cycle_day=22,
        log_chips=["work", "deadline"],
    )
    db_session.add(event)
    await db_session.flush()

    fetched = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == event.id))
    ).scalar_one()
    assert fetched.user_id == user.id
    assert fetched.detected_at == detected
    assert fetched.log_chips == ["work", "deadline"]
    assert fetched.logged is False
    assert fetched.notified is False


@pytest.mark.asyncio
async def test_stress_event_default_logged_false(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    event = StressEvent(
        user_id=user.id,
        detected_at=datetime(2026, 5, 6, 9, 0, tzinfo=UTC),
    )
    db_session.add(event)
    await db_session.flush()
    assert event.logged is False
    assert event.notified is False
    assert event.log_chips is None
    assert event.user_response is None
