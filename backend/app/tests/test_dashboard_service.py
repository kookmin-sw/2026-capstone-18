"""Unit tests for the dashboard aggregator service.

Service-level tests (not router-level) so we can probe each branch in isolation.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_aggregate_returns_all_nulls_for_new_user(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is None
    assert body.sleep is None
    assert body.mood is None
    assert body.events_count_24h == 0
    assert body.cycle is None


@pytest.mark.asyncio
async def test_aggregate_picks_user_stress_level_over_model(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)

    # Older logged event with user_stress_level=70.
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=4),
            logged=True,
            user_stress_level=70,
        )
    )
    # Newer model-only event (no user value, has confidence).
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=1),
            logged=False,
            model_confidence=0.9,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is not None
    assert body.stress.level == 70
    assert body.stress.source == "user"
    assert body.stress.logged is True


@pytest.mark.asyncio
async def test_aggregate_falls_back_to_model_confidence(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=2),
            logged=False,
            model_confidence=0.62,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is not None
    assert body.stress.level == 62  # 0.62 * 100
    assert body.stress.source == "model"


@pytest.mark.asyncio
async def test_aggregate_ignores_events_older_than_24h(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=30),
            logged=True,
            user_stress_level=99,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is None
    assert body.events_count_24h == 0


@pytest.mark.asyncio
async def test_aggregate_returns_latest_sleep_log(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    db_session.add(
        SleepLog(
            id=uuid.uuid4(),
            user_id=me.id,
            fell_asleep_at=datetime(2026, 5, 6, 23, tzinfo=UTC),
            woke_up_at=datetime(2026, 5, 7, 6, 30, tzinfo=UTC),
            ended_on=date(2026, 5, 7),
            rating="okay",
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.sleep is not None
    assert body.sleep.rating == "okay"
    assert body.sleep.ended_on == date(2026, 5, 7)
    assert body.sleep.total_minutes == 7 * 60 + 30


@pytest.mark.asyncio
async def test_aggregate_extracts_first_mood_chip(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=3),
            logged=True,
            mood_chips=["anxious", "overwhelmed"],
            user_stress_level=55,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.mood == "anxious"


@pytest.mark.asyncio
async def test_aggregate_computes_cycle_phase_and_days_left(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    today = datetime.now(tz=UTC).date()
    period_start = today - timedelta(days=18)  # ~ luteal day 19
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=period_start,
            cycle_length_days=28,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.cycle is not None
    assert body.cycle.phase == "luteal"
    assert body.cycle.day == 19
    # 28 - 19 + 1 = 10
    assert body.cycle.days_left_in_phase == 10
    assert body.cycle.cycle_length_days == 28


@pytest.mark.asyncio
async def test_aggregate_ignores_unlogged_user_stress_level(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """An event with user_stress_level set but logged=False must not surface as
    the dashboard stress card. user_stress_level only carries product meaning
    when the user has explicitly logged the event."""
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)

    # Unlogged event with user_stress_level (defensive: shouldn't happen today,
    # but lock the contract).
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=2),
            logged=False,
            user_stress_level=70,
            model_confidence=0.5,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    # Should fall back to model_confidence, not surface user_stress_level.
    assert body.stress is not None
    assert body.stress.source == "model"
    assert body.stress.level == 50  # 0.5 * 100


@pytest.mark.asyncio
async def test_dashboard_phase_respects_is_period_ongoing(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """When is_period_ongoing=True, the cycle phase must be 'menstrual' even
    when day > 5 (which would normally be 'follicular')."""
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    today = datetime.now(tz=UTC).date()
    # Set period_start 7 days ago so today is day 8.  Without the override,
    # day 8 falls in the follicular phase.
    period_start = today - timedelta(days=7)
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=period_start,
            cycle_length_days=28,
            is_period_ongoing=True,
        )
    )
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.cycle is not None
    assert body.cycle.phase == "menstrual"
    assert body.cycle.day == 8
