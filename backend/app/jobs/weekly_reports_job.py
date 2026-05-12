"""Weekly report generation job — triggered by EventBridge ECS RunTask."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

import structlog
from sqlalchemy import distinct, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent
from app.services.ai.weekly_report import WeeklyReportGenerator

logger = structlog.get_logger(__name__)


@dataclass(frozen=True)
class JobSummary:
    users_total: int
    reports_written: int
    failures: int


def _last_full_week_monday(today: date) -> date:
    """Return the Monday of the most-recently-completed week (relative to today)."""
    days_since_sunday = (today.weekday() + 1) % 7
    last_sunday = today - timedelta(days=days_since_sunday)
    return last_sunday - timedelta(days=6)


async def run_weekly_reports_job(
    db: AsyncSession,
    *,
    user_id_filter: list[str] | None = None,
    today: date | None = None,
) -> JobSummary:
    today = today or datetime.now(UTC).date()
    week_start = _last_full_week_monday(today)
    week_end = week_start + timedelta(days=6)
    start_dt = datetime.combine(week_start, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(week_end, datetime.max.time(), tzinfo=UTC)

    q = (
        select(distinct(StressEvent.user_id))
        .where(StressEvent.detected_at >= start_dt)
        .where(StressEvent.detected_at <= end_dt)
    )
    if user_id_filter:
        q = q.where(StressEvent.user_id.in_(user_id_filter))
    user_ids = list((await db.execute(q)).scalars().all())

    gen = WeeklyReportGenerator()
    written = 0
    failed = 0
    for uid in user_ids:
        try:
            async with db.begin_nested():  # savepoint per user — rolls back on exception
                await gen.generate(db, user_id=uid, week_start=week_start)
            written += 1
        except Exception as exc:  # noqa: BLE001
            logger.warning("weekly_report_failed", user_id=str(uid), error=str(exc))
            failed += 1
    await db.commit()
    return JobSummary(users_total=len(user_ids), reports_written=written, failures=failed)
