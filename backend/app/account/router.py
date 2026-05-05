"""Account router — /me, soft-delete, restore.

Sprint 3 implements the 30-day grace deletion as a `deleted_at` flag with a
window check on restore. A future sprint will add the cron job that hard-deletes
rows past the grace window; for now Sprint 3 just sets/clears the flag and lets
get_current_user reject deleted users with 403.
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
from app.schemas.user import AccountActionResponse, CurrentUserResponse

GRACE_WINDOW = timedelta(days=30)

router = APIRouter(tags=["account"])


@router.get("/me", response_model=CurrentUserResponse)
async def me(
    user: Annotated[User, Depends(get_current_user)],
) -> CurrentUserResponse:
    return CurrentUserResponse.model_validate(user)


@router.delete("/account", response_model=AccountActionResponse)
async def delete_account(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> AccountActionResponse:
    user.deleted_at = datetime.now(tz=UTC)
    await db.flush()
    return AccountActionResponse(status="ok", deleted_at=user.deleted_at)


@router.post("/account/restore", response_model=AccountActionResponse)
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
