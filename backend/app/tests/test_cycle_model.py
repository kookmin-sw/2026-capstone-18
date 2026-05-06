"""Cycle ORM model basics."""

from __future__ import annotations

import uuid
from datetime import date

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.user import User


@pytest.mark.asyncio
async def test_cycle_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    cycle = Cycle(
        user_id=user.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        auto_detected=False,
    )
    db_session.add(cycle)
    await db_session.flush()

    fetched = (await db_session.execute(select(Cycle).where(Cycle.id == cycle.id))).scalar_one()
    assert fetched.user_id == user.id
    assert fetched.period_start_date == date(2026, 5, 1)
    assert fetched.cycle_length_days == 28
    assert fetched.auto_detected is False
    assert fetched.user_corrected is False


@pytest.mark.asyncio
async def test_cycle_user_corrected_default_false(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    cycle = Cycle(user_id=user.id, period_start_date=date(2026, 5, 1))
    db_session.add(cycle)
    await db_session.flush()
    assert cycle.user_corrected is False
    assert cycle.cycle_length_days is None
