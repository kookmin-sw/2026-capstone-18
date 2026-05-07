"""Aggregator for /api/v1/dashboard/today.

Composes the dashboard payload from up to five independent queries (stress can
fan out to a second query when only a model-detected event is available, no
user-logged value). Returns a Pydantic model so the router can pass it straight
back to FastAPI without re-validating.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent
from app.schemas.dashboard import (
    DashboardCycle,
    DashboardSleep,
    DashboardStress,
    DashboardTodayResponse,
)
from app.services.cycle_phase import compute_phase, phase_window

WINDOW = timedelta(hours=24)


async def compute_dashboard_today(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
) -> DashboardTodayResponse:
    cutoff = datetime.now(tz=UTC) - WINDOW

    stress = await _stress(db, user_id=user_id, cutoff=cutoff)
    sleep = await _sleep(db, user_id=user_id)
    mood = await _mood(db, user_id=user_id, cutoff=cutoff)
    events_count = await _events_count(db, user_id=user_id, cutoff=cutoff)
    cycle = await _cycle(db, user_id=user_id)

    return DashboardTodayResponse(
        stress=stress,
        sleep=sleep,
        mood=mood,
        events_count_24h=events_count,
        cycle=cycle,
    )


async def _stress(
    db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime
) -> DashboardStress | None:
    # Prefer the most recent logged event with a user-rated value.
    user_rated = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.logged.is_(True),
                StressEvent.user_stress_level.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if user_rated is not None:
        assert user_rated.user_stress_level is not None  # guaranteed by WHERE
        return DashboardStress(
            level=int(user_rated.user_stress_level),
            source="user",
            detected_at=user_rated.detected_at,
            logged=user_rated.logged,
        )

    # Fall back to model confidence on the most recent event.
    model_only = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.model_confidence.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if model_only is not None:
        assert model_only.model_confidence is not None  # guaranteed by WHERE
        return DashboardStress(
            level=int(round(model_only.model_confidence * 100)),
            source="model",
            detected_at=model_only.detected_at,
            logged=model_only.logged,
        )

    return None


async def _sleep(db: AsyncSession, *, user_id: uuid.UUID) -> DashboardSleep | None:
    row = (
        await db.execute(
            select(SleepLog)
            .where(SleepLog.user_id == user_id)
            .order_by(SleepLog.ended_on.desc(), SleepLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    return DashboardSleep(
        total_minutes=row.total_minutes,
        rating=row.rating,
        ended_on=row.ended_on,
    )


async def _mood(db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime) -> str | None:
    row = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.logged.is_(True),
                StressEvent.mood_chips.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None or not row.mood_chips:
        return None
    return row.mood_chips[0]


async def _events_count(db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime) -> int:
    return int(
        (
            await db.execute(
                select(func.count(StressEvent.id)).where(
                    StressEvent.user_id == user_id,
                    StressEvent.detected_at >= cutoff,
                )
            )
        ).scalar_one()
    )


async def _cycle(db: AsyncSession, *, user_id: uuid.UUID) -> DashboardCycle | None:
    row = (
        await db.execute(
            select(Cycle)
            .where(Cycle.user_id == user_id)
            .order_by(Cycle.period_start_date.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    cycle_length = row.cycle_length_days or 28
    today = datetime.now(tz=UTC).date()
    phase, day = compute_phase(
        today=today,
        period_start_date=row.period_start_date,
        cycle_length_days=cycle_length,
    )
    days_left = phase_window(phase=phase, day=day, cycle_length_days=cycle_length)
    return DashboardCycle(
        phase=phase,
        day=day,
        days_left_in_phase=days_left,
        cycle_length_days=cycle_length,
        period_start_date=row.period_start_date,
    )
