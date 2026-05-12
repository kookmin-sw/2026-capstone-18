"""GET /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func as sa_func
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.range_report import RangeReport
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent
from app.models.user import User
from app.models.weekly_report import WeeklyReport
from app.schemas.reports import (
    DrilldownResponse,
    RangeReportResponse,
    Takeaway,
    WeeklyReportResponse,
)
from app.services.ai.range_report import RangeReportGenerator
from app.services.reports.drilldown import compute_drilldown

router = APIRouter(prefix="/reports", tags=["reports"])

_DEFAULT_WINDOW = timedelta(days=90)
_VALID_PHASES = {"menstrual", "follicular", "ovulation", "luteal"}


@router.get(
    "/drilldown",
    response_model=DrilldownResponse,
    summary="Per (category, phase) report — summary, heatmap, recent events",
)
async def drilldown(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    phase: Annotated[str, Query()],
    category_id: Annotated[uuid.UUID | None, Query()] = None,
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> DrilldownResponse:
    if phase not in _VALID_PHASES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "unsupported_phase"},
        )
    today = datetime.now(tz=UTC).date()
    f = frm or today - _DEFAULT_WINDOW
    t = to or today
    if f > t:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "frm_must_be_le_to"},
        )
    return await compute_drilldown(
        db,
        user_id=user.id,
        category_id=category_id,
        phase=phase,
        frm=f,
        to=t,
    )


@router.get(
    "/weekly",
    response_model=WeeklyReportResponse,
    summary="Latest AI-generated weekly report for the current user",
)
async def get_latest_weekly_report(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> WeeklyReportResponse:
    settings = get_settings()
    if not settings.ai_features_enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "ai_disabled"},
        )
    row = (
        await db.execute(
            select(WeeklyReport)
            .where(WeeklyReport.user_id == user.id)
            .order_by(WeeklyReport.week_start.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "no_report"},
        )
    return WeeklyReportResponse(
        week_start=row.week_start,
        headline=row.headline,
        body_md=row.body_md,
        takeaways=[Takeaway(**t) for t in row.takeaways],
        generated_at=row.generated_at,
    )


@router.get(
    "/range",
    response_model=RangeReportResponse,
    summary="AI report for a user-selected date range, cached per (user, frm, to)",
)
async def get_range_report(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date, Query()],
    to: Annotated[date, Query()],
) -> RangeReportResponse:
    settings = get_settings()
    if not settings.ai_features_enabled:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "ai_disabled"},
        )
    if frm > to:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "frm_must_be_le_to"},
        )

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    cached = (
        await db.execute(
            select(RangeReport).where(
                RangeReport.user_id == user.id,
                RangeReport.period_start == frm,
                RangeReport.period_end == to,
            )
        )
    ).scalar_one_or_none()

    latest_event_ts = (
        await db.execute(
            select(sa_func.max(StressEvent.created_at))
            .where(StressEvent.user_id == user.id)
            .where(StressEvent.detected_at >= start_dt)
            .where(StressEvent.detected_at <= end_dt)
        )
    ).scalar_one()
    latest_sleep_ts = (
        await db.execute(
            select(sa_func.max(SleepLog.created_at))
            .where(SleepLog.user_id == user.id)
            .where(SleepLog.ended_on >= frm)
            .where(SleepLog.ended_on <= to)
        )
    ).scalar_one()
    latest_data_ts = max(
        (t for t in (latest_event_ts, latest_sleep_ts) if t is not None),
        default=None,
    )

    if cached is not None and (latest_data_ts is None or cached.generated_at >= latest_data_ts):
        return RangeReportResponse(
            period_start=cached.period_start,
            period_end=cached.period_end,
            headline=cached.headline,
            body_md=cached.body_md,
            takeaways=[Takeaway(**t) for t in cached.takeaways],
            generated_at=cached.generated_at,
        )

    gen = RangeReportGenerator()
    fresh = await gen.generate(db, user_id=user.id, period_start=frm, period_end=to)
    return RangeReportResponse(
        period_start=fresh.period_start,
        period_end=fresh.period_end,
        headline=fresh.headline,
        body_md=fresh.body_md,
        takeaways=[Takeaway(**t) for t in fresh.takeaways],
        generated_at=datetime.now(UTC),
    )
