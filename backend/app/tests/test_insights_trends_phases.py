from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_trends_returns_per_day_avg(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.trends import compute_trends

    me = await make_user()
    base = datetime(2026, 5, 1, 9, tzinfo=UTC)
    db_session.add(
        StressEvent(
            id=uuid.uuid4(), user_id=me.id, detected_at=base, logged=True, user_stress_level=40
        )
    )
    db_session.add(
        StressEvent(
            id=uuid.uuid4(), user_id=me.id, detected_at=base, logged=True, user_stress_level=80
        )
    )
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=base + timedelta(days=2),
            logged=True,
            user_stress_level=50,
        )
    )
    await db_session.flush()

    body = await compute_trends(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 7),
    )
    by_day = {p.date: (p.avg_stress, p.event_count) for p in body.points}
    assert by_day[date(2026, 5, 1)] == (60.0, 2)
    assert by_day[date(2026, 5, 3)] == (50.0, 1)


@pytest.mark.asyncio
async def test_phase_averages_groups_by_phase(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.phase_averages import compute_phase_averages

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 5, 1),
            cycle_length_days=28,
        )
    )
    # Day 2 → menstrual: 40
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 5, 2, 10, tzinfo=UTC),
            logged=True,
            user_stress_level=40,
        )
    )
    # Day 19 → luteal: 70 and 90
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
            logged=True,
            user_stress_level=70,
        )
    )
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 5, 19, 12, tzinfo=UTC),
            logged=True,
            user_stress_level=90,
        )
    )
    await db_session.flush()

    body = await compute_phase_averages(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 31),
    )
    by_phase = {p.phase: p for p in body.phases}
    assert by_phase["menstrual"].avg_stress == 40.0
    assert by_phase["menstrual"].event_count == 1
    assert by_phase["luteal"].avg_stress == 80.0
    assert by_phase["luteal"].event_count == 2
