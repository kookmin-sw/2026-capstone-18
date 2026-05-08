"""Service-level tests for compute_drilldown."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory


@pytest.mark.asyncio
async def test_drilldown_for_empty_user_returns_zero_summary(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,
        phase="luteal",
        frm=date(2026, 5, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 0
    assert body.summary.avg_stress is None
    assert body.summary.top_mood is None
    assert body.summary.most_common_day is None
    # Heatmap still shows the canonical day grid for the phase, with zeros.
    assert {d.day for d in body.heatmap} == {17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28}
    assert all(d.event_count == 0 and d.avg_stress is None for d in body.heatmap)
    assert body.recent_events == []


@pytest.mark.asyncio
async def test_drilldown_aggregates_for_category_phase(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 9, 1),  # so day 19 = Sept 19, day 20 = Sept 20
            cycle_length_days=28,
        )
    )
    work = TriggerCategory(
        id=uuid.uuid4(),
        user_id=me.id,
        name="Work",
        color="#7C3AED",
        sort_order=0,
    )
    db_session.add(work)
    await db_session.flush()

    # 3 events on cycle day 20 — should be most_common_day.
    for level in (70, 78, 75):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 9, 20, 14, tzinfo=UTC),
                logged=True,
                user_stress_level=level,
                mood_chips=["anxious"],
                category_id=work.id,
            )
        )
    # 2 events on day 19.
    for level in (60, 65):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 9, 19, 9, tzinfo=UTC),
                logged=True,
                user_stress_level=level,
                mood_chips=["overwhelmed"],
                category_id=work.id,
            )
        )
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=work.id,
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 5
    assert body.summary.avg_stress == round((70 + 78 + 75 + 60 + 65) / 5, 2)
    assert body.summary.top_mood == "anxious"  # 3 vs 2
    assert body.summary.most_common_day == 20

    by_day = {d.day: d for d in body.heatmap}
    assert by_day[20].event_count == 3
    assert by_day[20].avg_stress == round((70 + 78 + 75) / 3, 2)
    assert by_day[19].event_count == 2
    assert by_day[17].event_count == 0  # untouched cells appear with zero

    assert len(body.recent_events) == 5  # all five fit under the 10-cap
    # Newest first.
    assert body.recent_events[0].cycle_day == 20


@pytest.mark.asyncio
async def test_drilldown_filters_by_uncategorized_when_category_id_none(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 9, 1),
            cycle_length_days=28,
        )
    )
    work = TriggerCategory(
        id=uuid.uuid4(),
        user_id=me.id,
        name="Work",
        color="#7C3AED",
        sort_order=0,
    )
    db_session.add(work)
    await db_session.flush()

    # categorized
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 9, 20, tzinfo=UTC),
            logged=True,
            user_stress_level=80,
            category_id=work.id,
        )
    )
    # uncategorized
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 9, 21, tzinfo=UTC),
            logged=True,
            user_stress_level=40,
        )
    )
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,  # filter for uncategorized only
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 1
    assert body.summary.category_name == "Uncategorized"
    assert body.summary.avg_stress == 40.0


@pytest.mark.asyncio
async def test_drilldown_caps_recent_events_at_10(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 9, 1),
            cycle_length_days=28,
        )
    )
    await db_session.flush()
    for hour in range(15):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 9, 20, hour, tzinfo=UTC),
                logged=True,
                user_stress_level=50,
            )
        )
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert len(body.recent_events) == 10
