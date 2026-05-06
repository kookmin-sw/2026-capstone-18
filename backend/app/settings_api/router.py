"""GET/PATCH /api/v1/settings."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.models.user_settings import UserSettings
from app.schemas.settings import UserSettingsResponse, UserSettingsUpdate
from app.services.user_settings import ensure_user_settings

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get(
    "",
    response_model=UserSettingsResponse,
    summary="Get the caller's notification + locale preferences",
)
async def get_settings(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserSettings:
    return await ensure_user_settings(db, user)


@router.patch(
    "",
    response_model=UserSettingsResponse,
    summary="Update notification + locale preferences",
)
async def patch_settings(
    payload: UserSettingsUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> UserSettings:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    settings = await ensure_user_settings(db, user)
    if payload.notification_max_per_day is not None:
        settings.notification_max_per_day = payload.notification_max_per_day
    if payload.stress_threshold is not None:
        settings.stress_threshold = payload.stress_threshold
    if payload.quiet_hours_start is not None:
        settings.quiet_hours_start = payload.quiet_hours_start
    if payload.quiet_hours_end is not None:
        settings.quiet_hours_end = payload.quiet_hours_end
    if payload.silence_during_meeting is not None:
        settings.silence_during_meeting = payload.silence_during_meeting
    if payload.silence_during_exercise is not None:
        settings.silence_during_exercise = payload.silence_during_exercise
    if payload.consent_audit_logging is not None:
        settings.consent_audit_logging = payload.consent_audit_logging
    if payload.language is not None:
        settings.language = payload.language
    await db.flush()
    await db.refresh(settings)
    return settings
