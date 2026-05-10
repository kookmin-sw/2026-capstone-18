"""GET /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.user import User
from app.models.weekly_report import WeeklyReport
from app.schemas.reports import DrilldownResponse, Takeaway, WeeklyReportResponse
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
