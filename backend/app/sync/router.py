"""/api/v1/sync — encrypted backup blobs."""

from __future__ import annotations

import uuid
from typing import Annotated, Literal

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.sync_blob import SyncBlob
from app.models.user import User
from app.schemas.sync import (
    SyncDownloadResponse,
    SyncUploadRequest,
    SyncUploadResponse,
)
from app.services.s3 import delete_object, presign_get, presign_put

router = APIRouter(prefix="/sync", tags=["sync"])
logger = structlog.get_logger(__name__)


@router.post(
    "/upload",
    response_model=SyncUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Get a presigned URL to upload an encrypted backup blob",
)
async def sync_upload(
    payload: SyncUploadRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SyncUploadResponse:
    settings = get_settings()
    blob_id = uuid.uuid4()
    object_key = f"users/{user.id}/{payload.kind}/{blob_id}.bin"

    blob = SyncBlob(
        id=blob_id,
        user_id=user.id,
        s3_object_key=object_key,
        kind=payload.kind,
        byte_size=payload.byte_size,
    )
    db.add(blob)
    await db.flush()

    url = await presign_put(
        bucket=settings.s3_bucket_sync,
        key=object_key,
        content_length=payload.byte_size,
        expires_in=settings.s3_presign_expiry_seconds,
    )
    return SyncUploadResponse(
        blob_id=blob_id,
        s3_object_key=object_key,
        presigned_put_url=url,
        expires_in=settings.s3_presign_expiry_seconds,
    )


@router.get(
    "/download",
    response_model=SyncDownloadResponse,
    summary="Get a presigned URL to download the latest encrypted backup blob",
)
async def sync_download(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    kind: Annotated[Literal["backup"], Query()] = "backup",
) -> SyncDownloadResponse:
    row = (
        await db.execute(
            select(SyncBlob)
            .where(SyncBlob.user_id == user.id, SyncBlob.kind == kind)
            .order_by(SyncBlob.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "no_backup"},
        )
    settings = get_settings()
    url = await presign_get(
        bucket=settings.s3_bucket_sync,
        key=row.s3_object_key,
        expires_in=settings.s3_presign_expiry_seconds,
    )
    return SyncDownloadResponse(
        blob_id=row.id,
        s3_object_key=row.s3_object_key,
        presigned_get_url=url,
        byte_size=row.byte_size,
        created_at=row.created_at,
    )


@router.delete(
    "",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Wipe all of the caller's backup blobs from S3 and the registry",
)
async def sync_wipe(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    settings = get_settings()
    rows = (await db.execute(select(SyncBlob).where(SyncBlob.user_id == user.id))).scalars().all()
    for row in rows:
        try:
            await delete_object(bucket=settings.s3_bucket_sync, key=row.s3_object_key)
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "sync_s3_delete_failed",
                user_id=str(user.id),
                key=row.s3_object_key,
                error=str(exc),
            )
    await db.execute(delete(SyncBlob).where(SyncBlob.user_id == user.id))
    await db.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
