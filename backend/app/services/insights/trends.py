"""Per-day average stress over a date range."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent
from app.schemas.insights import InsightsTrendsResponse, TrendPoint


async def compute_trends(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    frm: date,
    to: date,
) -> InsightsTrendsResponse:
    if frm > to:
        raise ValueError("frm must be <= to")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

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
        )
        .group_by(day_col)
    )
    rows = (await db.execute(stmt)).all()
    by_day: dict[date, tuple[int, float | None]] = {}
    for day_dt, count, avg in rows:
        d = day_dt.date() if hasattr(day_dt, "date") else day_dt
        by_day[d] = (int(count), float(avg) if avg is not None else None)

    points: list[TrendPoint] = []
    cur = frm
    while cur <= to:
        count, avg = by_day.get(cur, (0, None))
        points.append(TrendPoint(date=cur, avg_stress=avg, event_count=count))
        cur += timedelta(days=1)

    return InsightsTrendsResponse(points=points)
