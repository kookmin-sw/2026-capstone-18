"""POST /api/v1/devices/fcm-token — register or refresh an FCM token."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.fcm_token import FcmToken
from app.models.user import User
from app.schemas.devices import FcmTokenRegister, FcmTokenResponse, FcmTokenUnregister

router = APIRouter(prefix="/devices", tags=["devices"])


@router.post(
    "/fcm-token",
    response_model=FcmTokenResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Register or refresh an FCM device token",
)
async def register_fcm_token(
    payload: FcmTokenRegister,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> FcmToken:
    existing = (
        await db.execute(
            select(FcmToken).where(FcmToken.user_id == user.id, FcmToken.token == payload.token)
        )
    ).scalar_one_or_none()
    if existing is not None:
        existing.platform = payload.platform
        existing.last_seen_at = datetime.now(tz=UTC)
        await db.flush()
        await db.refresh(existing)
        return existing
    row = FcmToken(user_id=user.id, token=payload.token, platform=payload.platform)
    db.add(row)
    await db.flush()
    await db.refresh(row)
    return row


@router.delete(
    "/fcm-token",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Unregister an FCM device token (idempotent)",
)
async def unregister_fcm_token(
    payload: FcmTokenUnregister,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    """Delete the row matching (user, token). 204 even if the row never existed
    so callers don't learn whether a token was registered."""
    await db.execute(
        delete(FcmToken).where(
            FcmToken.user_id == user.id,
            FcmToken.token == payload.token,
        )
    )
