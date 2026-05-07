from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_calendar_for_empty_user_returns_full_month_grid(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    assert body.month == "2026-05"
    assert len(body.days) == 31  # May has 31 days
    assert all(d.event_count == 0 and d.avg_stress is None for d in body.days)
    assert all(d.phase == "pre_period" for d in body.days)


@pytest.mark.asyncio
async def test_calendar_overlays_phase_from_cycle(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 5, 1),
            cycle_length_days=28,
        )
    )
    await db_session.flush()

    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    by_day = {d.date.day: d.phase for d in body.days}
    assert by_day[1] == "menstrual"  # day 1
    assert by_day[5] == "menstrual"  # day 5
    assert by_day[6] == "follicular"  # day 6
    assert by_day[14] == "ovulation"  # day 14
    assert by_day[17] == "luteal"  # day 17


@pytest.mark.asyncio
async def test_calendar_aggregates_event_counts_and_avg(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    for level in (40, 80):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 5, 14, 10, tzinfo=UTC),
                logged=True,
                user_stress_level=level,
            )
        )
    await db_session.flush()

    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    day14 = next(d for d in body.days if d.date.day == 14)
    assert day14.event_count == 2
    assert day14.avg_stress == 60.0  # (40 + 80) / 2
