"""GET /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.reports import DrilldownResponse
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
