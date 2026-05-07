"""GET /api/v1/insights/{calendar,trends,phase-averages,heatmap,patterns}."""

from __future__ import annotations

import re
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.insights import (
    InsightsCalendarResponse,
    InsightsHeatmapResponse,
    InsightsPatternsResponse,
    InsightsPhaseAveragesResponse,
    InsightsTrendsResponse,
)
from app.services.insights.calendar import compute_calendar
from app.services.insights.heatmap import compute_heatmap
from app.services.insights.patterns import compute_patterns
from app.services.insights.phase_averages import compute_phase_averages
from app.services.insights.trends import compute_trends

router = APIRouter(prefix="/insights", tags=["insights"])

_MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
_DEFAULT_WINDOW = timedelta(days=30)


def _default_range() -> tuple[date, date]:
    today = datetime.now(tz=UTC).date()
    # Produce exactly 30 points: days [today-30, today-1] inclusive.
    return today - _DEFAULT_WINDOW, today - timedelta(days=1)


def _validate_range(frm: date | None, to: date | None) -> tuple[date, date]:
    default_frm, default_to = _default_range()
    f = frm or default_frm
    t = to or default_to
    if f > t:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "frm_must_be_le_to"},
        )
    return f, t


@router.get("/calendar", response_model=InsightsCalendarResponse)
async def calendar(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    month: Annotated[str, Query()],
) -> InsightsCalendarResponse:
    if not _MONTH_RE.match(month):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "invalid_month"},
        )
    return await compute_calendar(db, user_id=user.id, month=month)


@router.get("/trends", response_model=InsightsTrendsResponse)
async def trends(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsTrendsResponse:
    f, t = _validate_range(frm, to)
    return await compute_trends(db, user_id=user.id, frm=f, to=t)


@router.get("/phase-averages", response_model=InsightsPhaseAveragesResponse)
async def phase_averages(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsPhaseAveragesResponse:
    f, t = _validate_range(frm, to)
    return await compute_phase_averages(db, user_id=user.id, frm=f, to=t)


@router.get("/heatmap", response_model=InsightsHeatmapResponse)
async def heatmap(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsHeatmapResponse:
    f, t = _validate_range(frm, to)
    return await compute_heatmap(db, user_id=user.id, frm=f, to=t)


@router.get("/patterns", response_model=InsightsPatternsResponse)
async def patterns(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsPatternsResponse:
    f, t = _validate_range(frm, to)
    return await compute_patterns(db, user_id=user.id, frm=f, to=t)
