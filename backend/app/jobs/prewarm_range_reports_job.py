"""Nightly prewarm job for AI range reports.

Triggered by EventBridge → ECS RunTask. For every user with stress activity in
the last 30 days, we pre-generate range reports for the canonical 7/14/30-day
ranges ending today. Subsequent user views read from the `range_reports` cache
table (~70ms) instead of waking Bedrock (~8s).

Idempotent: skips users whose cached row is fresher than the latest stress
event in that range. Per-user savepoints so one user's Bedrock failure does
not roll back the whole job.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta

import structlog
from sqlalchemy import distinct, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.range_report import RangeReport
from app.models.stress_event import StressEvent
from app.services.ai.range_report import RangeReportGenerator

logger = structlog.get_logger(__name__)

# Canonical ranges the app exposes by default in the AI Report UI.
CANONICAL_RANGE_DAYS: tuple[int, ...] = (7, 14, 30)

# Only warm users with at least one event in this lookback window.
ACTIVE_WINDOW_DAYS = 30


@dataclass(frozen=True)
class PrewarmSummary:
    users_total: int
    reports_written: int
    reports_skipped_cache_fresh: int
    failures: int


async def _is_cache_fresh(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    period_start: date,
    period_end: date,
) -> bool:
    """Return True if a cached range_reports row exists for this exact tuple AND
    its generated_at is >= the latest stress event in the range."""
    cached = (
        await db.execute(
            select(RangeReport).where(
                RangeReport.user_id == user_id,
                RangeReport.period_start == period_start,
                RangeReport.period_end == period_end,
            )
        )
    ).scalar_one_or_none()
    if cached is None:
        return False

    start_dt = datetime.combine(period_start, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(period_end, datetime.max.time(), tzinfo=UTC)
    latest_event_ts = (
        await db.execute(
            select(func.max(StressEvent.created_at))
            .where(StressEvent.user_id == user_id)
            .where(StressEvent.detected_at >= start_dt)
            .where(StressEvent.detected_at <= end_dt)
        )
    ).scalar_one()
    if latest_event_ts is None:
        # No events to invalidate against — cache is trivially fresh.
        return True
    return bool(cached.generated_at >= latest_event_ts)


async def run_prewarm_range_reports_job(
    db: AsyncSession,
    *,
    user_id_filter: list[str] | None = None,
    today: date | None = None,
) -> PrewarmSummary:
    today = today or datetime.now(UTC).date()
    active_since = datetime.combine(
        today - timedelta(days=ACTIVE_WINDOW_DAYS),
        datetime.min.time(),
        tzinfo=UTC,
    )

    q = select(distinct(StressEvent.user_id)).where(StressEvent.detected_at >= active_since)
    if user_id_filter:
        q = q.where(StressEvent.user_id.in_(user_id_filter))
    user_ids = list((await db.execute(q)).scalars().all())

    gen = RangeReportGenerator()
    written = 0
    skipped = 0
    failed = 0

    for uid in user_ids:
        for days in CANONICAL_RANGE_DAYS:
            period_start = today - timedelta(days=days)
            period_end = today
            try:
                if await _is_cache_fresh(
                    db, user_id=uid, period_start=period_start, period_end=period_end
                ):
                    skipped += 1
                    continue
                async with db.begin_nested():  # savepoint per (user, range)
                    await gen.generate(
                        db,
                        user_id=uid,
                        period_start=period_start,
                        period_end=period_end,
                    )
                written += 1
                logger.info(
                    "prewarm_range_written",
                    user_id=str(uid),
                    period_start=str(period_start),
                    period_end=str(period_end),
                )
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "prewarm_range_failed",
                    user_id=str(uid),
                    period_start=str(period_start),
                    period_end=str(period_end),
                    error=str(exc),
                    exc_type=type(exc).__name__,
                )
                failed += 1

    await db.commit()
    return PrewarmSummary(
        users_total=len(user_ids),
        reports_written=written,
        reports_skipped_cache_fresh=skipped,
        failures=failed,
    )
