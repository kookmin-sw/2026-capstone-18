"""GET /api/v1/dashboard/today."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.dashboard import DashboardTodayResponse
from app.services.dashboard import compute_dashboard_today

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get(
    "/today",
    response_model=DashboardTodayResponse,
    summary="Single-shot home screen aggregate",
)
async def get_today(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> DashboardTodayResponse:
    return await compute_dashboard_today(db, user_id=user.id)
