"""/api/v1/sync — encrypted backup blobs."""

from __future__ import annotations

import uuid
from datetime import timedelta
from typing import Annotated, Literal

import structlog
from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.raw_biosignal_upload import RawBiosignalUpload
from app.models.sync_blob import SyncBlob
from app.models.user import User
from app.schemas.sync import (
    BiosignalBatchUploadRequest,
    BiosignalBatchUploadResponse,
    BiosignalUploadRequest,
    BiosignalUploadResponse,
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


@router.post(
    "/biosignals",
    response_model=BiosignalUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Get a presigned URL to upload an opt-in raw biosignal blob",
)
async def biosignals_upload(
    payload: BiosignalUploadRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BiosignalUploadResponse:
    if not user.consent_raw_biosignals or user.consent_revoked_at is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "reason": "consent_required"},
        )

    settings = get_settings()
    upload_id = uuid.uuid4()
    object_key = f"users/{user.id}/biosignals/{payload.signal_type}/{upload_id}.bin"
    expires_at = payload.recorded_at + timedelta(days=365)

    row = RawBiosignalUpload(
        id=upload_id,
        user_id=user.id,
        s3_object_key=object_key,
        signal_type=payload.signal_type,
        recorded_at=payload.recorded_at,
        expires_at=expires_at,
    )
    db.add(row)
    await db.flush()

    url = await presign_put(
        bucket=settings.s3_bucket_biosignals,
        key=object_key,
        content_length=payload.byte_size,
        expires_in=settings.s3_presign_expiry_seconds,
    )
    return BiosignalUploadResponse(
        upload_id=upload_id,
        s3_object_key=object_key,
        presigned_put_url=url,
        expires_in=settings.s3_presign_expiry_seconds,
        expires_at=expires_at,
    )


@router.post(
    "/biosignals/batch",
    response_model=BiosignalBatchUploadResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Get presigned URLs for multiple raw biosignal blobs in one request",
)
async def biosignals_batch_upload(
    payload: BiosignalBatchUploadRequest,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> BiosignalBatchUploadResponse:
    if not user.consent_raw_biosignals or user.consent_revoked_at is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "reason": "consent_required"},
        )

    settings = get_settings()
    response_items: list[BiosignalUploadResponse] = []
    for item in payload.items:
        upload_id = uuid.uuid4()
        object_key = f"users/{user.id}/biosignals/{item.signal_type}/{upload_id}.bin"
        expires_at = item.recorded_at + timedelta(days=365)

        row = RawBiosignalUpload(
            id=upload_id,
            user_id=user.id,
            s3_object_key=object_key,
            signal_type=item.signal_type,
            recorded_at=item.recorded_at,
            expires_at=expires_at,
        )
        db.add(row)

        url = await presign_put(
            bucket=settings.s3_bucket_biosignals,
            key=object_key,
            content_length=item.byte_size,
            expires_in=settings.s3_presign_expiry_seconds,
        )
        response_items.append(
            BiosignalUploadResponse(
                upload_id=upload_id,
                s3_object_key=object_key,
                presigned_put_url=url,
                expires_in=settings.s3_presign_expiry_seconds,
                expires_at=expires_at,
            )
        )
    await db.flush()
    return BiosignalBatchUploadResponse(items=response_items)
