"""GET/PATCH /api/v1/consent.

Sprint 4 only flips flags. Sprint 6 will add the deletion job that hard-deletes
S3 raw biosignal blobs after `consent_revoked_at` is set.
"""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.consent import ConsentResponse, ConsentUpdate
from app.services.user_settings import ensure_user_settings

router = APIRouter(prefix="/consent", tags=["consent"])


def _project(user: User, audit_logging: bool) -> ConsentResponse:
    return ConsentResponse(
        consent_raw_biosignals=user.consent_raw_biosignals,
        consent_revoked_at=user.consent_revoked_at,
        consent_audit_logging=audit_logging,
    )


@router.get(
    "",
    response_model=ConsentResponse,
    summary="Get current consent state",
)
async def get_consent(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ConsentResponse:
    settings = await ensure_user_settings(db, user)
    return _project(user, settings.consent_audit_logging)


@router.patch(
    "",
    response_model=ConsentResponse,
    summary="Update consent toggles",
)
async def patch_consent(
    payload: ConsentUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> ConsentResponse:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    settings = await ensure_user_settings(db, user)

    if payload.consent_raw_biosignals is not None:
        previous = user.consent_raw_biosignals
        user.consent_raw_biosignals = payload.consent_raw_biosignals
        if previous and not payload.consent_raw_biosignals:
            user.consent_revoked_at = datetime.now(tz=UTC)
        elif not previous and payload.consent_raw_biosignals:
            user.consent_revoked_at = None
    if payload.consent_audit_logging is not None:
        settings.consent_audit_logging = payload.consent_audit_logging

    await db.flush()
    await db.refresh(user)
    await db.refresh(settings)
    return _project(user, settings.consent_audit_logging)
