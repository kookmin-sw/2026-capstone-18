"""Account router — /me, soft-delete, restore.

Sprint 3 stores the 30-day grace deletion as a `deleted_at` flag with a
window check on restore. Sprint 6 added `app.services.deletion.purge_expired_accounts`,
which the in-process loop in `app.main` runs hourly to hard-delete rows whose
`deleted_at` is older than `Settings.account_grace_window_days`.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user, get_current_user_id
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.user import AccountActionResponse, CurrentUserResponse, MeUpdate

GRACE_WINDOW = timedelta(days=30)

router = APIRouter(tags=["account"])


@router.get(
    "/me", response_model=CurrentUserResponse, summary="Return the authenticated user's profile"
)
async def me(
    user: Annotated[User, Depends(get_current_user)],
) -> CurrentUserResponse:
    return CurrentUserResponse.model_validate(user)


@router.patch(
    "/me",
    response_model=CurrentUserResponse,
    summary="Update the authenticated user's profile",
)
async def patch_me(
    payload: MeUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CurrentUserResponse:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    if "display_name" in payload.model_fields_set:
        user.display_name = payload.display_name
    await db.flush()
    await db.refresh(user)
    return CurrentUserResponse.model_validate(user)


@router.delete(
    "/account", response_model=AccountActionResponse, summary="Initiate the 30-day grace deletion"
)
async def delete_account(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AccountActionResponse:
    user.deleted_at = datetime.now(tz=UTC)
    await db.flush()
    return AccountActionResponse(status="ok", deleted_at=user.deleted_at)


@router.post(
    "/account/restore",
    response_model=AccountActionResponse,
    summary="Cancel a pending deletion within the grace window",
)
async def restore_account(
    user_id: Annotated[uuid.UUID, Depends(get_current_user_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AccountActionResponse:
    # Look up by Supabase user_id directly — get_current_user would 403 because deleted_at is set.
    row = (
        await db.execute(select(User).where(User.supabase_user_id == user_id))
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "user_not_found"},
        )
    if row.deleted_at is None:
        return AccountActionResponse(status="ok", deleted_at=None)
    if datetime.now(tz=UTC) - row.deleted_at > GRACE_WINDOW:
        raise HTTPException(
            status_code=status.HTTP_410_GONE,
            detail={"status": "error", "reason": "grace_window_expired"},
        )
    row.deleted_at = None
    await db.flush()
    return AccountActionResponse(status="ok", deleted_at=None)
