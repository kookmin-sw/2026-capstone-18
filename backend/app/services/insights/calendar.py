"""Per-month calendar grid: phase + event counts + avg user_stress_level."""

from __future__ import annotations

import calendar as _cal
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.schemas.insights import CalendarDay, InsightsCalendarResponse
from app.services.insights.cycle_lookup import CycleSnapshot, classify


async def compute_calendar(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    month: str,  # "YYYY-MM"
) -> InsightsCalendarResponse:
    year_str, month_str = month.split("-")
    year = int(year_str)
    mo = int(month_str)
    if not (1 <= mo <= 12):
        raise ValueError(f"month out of range: {month!r}")

    last_day = _cal.monthrange(year, mo)[1]
    first = date(year, mo, 1)
    last = date(year, mo, last_day)
    start_dt = datetime.combine(first, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(last, datetime.max.time(), tzinfo=UTC)

    # Cycle index for phase classification.
    cycles = (await db.execute(select(Cycle).where(Cycle.user_id == user_id))).scalars().all()
    classifier = classify(
        cycles=[
            CycleSnapshot(
                period_start_date=c.period_start_date,
                cycle_length_days=c.cycle_length_days or 28,
            )
            for c in cycles
        ]
    )

    # Aggregate events by day.
    day_col = func.date_trunc("day", StressEvent.detected_at).label("day")
    stmt = (
        select(
            day_col,
            func.count(StressEvent.id).label("event_count"),
            func.avg(StressEvent.user_stress_level).label("avg_stress"),
        )
        .where(
            StressEvent.user_id == user_id,
            StressEvent.detected_at >= start_dt,
            StressEvent.detected_at <= end_dt,
            StressEvent.logged.is_(True),
        )
        .group_by(day_col)
    )
    rows = (await db.execute(stmt)).all()
    by_day: dict[date, tuple[int, float | None]] = {}
    for day_dt, count, avg in rows:
        d = day_dt.date() if hasattr(day_dt, "date") else day_dt
        by_day[d] = (int(count), float(avg) if avg is not None else None)

    days: list[CalendarDay] = []
    cur = first
    while cur <= last:
        phase, _ = classifier(datetime.combine(cur, datetime.min.time(), tzinfo=UTC))
        count, avg = by_day.get(cur, (0, None))
        days.append(CalendarDay(date=cur, phase=phase, event_count=count, avg_stress=avg))
        cur = cur + timedelta(days=1)

    return InsightsCalendarResponse(month=month, days=days)
