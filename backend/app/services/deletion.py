"""Privacy + deletion jobs.

`purge_expired_accounts` walks `users` for soft-deleted rows past the grace
window and hard-deletes them. `purge_revoked_biosignals` walks `users` whose
`consent_revoked_at` is set and deletes their raw biosignal uploads.

Both jobs follow the best-effort S3 pattern from `sync_wipe`: log a warning
on S3 errors but proceed with the DB delete. Sprint 7 (EventBridge) will
swap the in-process scheduler in `app.main` for a managed cron.
"""

from __future__ import annotations

import uuid

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.raw_biosignal_upload import RawBiosignalUpload
from app.models.sync_blob import SyncBlob
from app.services.s3 import delete_object

logger = structlog.get_logger(__name__)


async def _delete_s3_keys_best_effort(keys: list[tuple[str, str]]) -> int:
    """Delete each (bucket, key). Return count successfully deleted.

    Errors are logged but never raised — the caller wants to proceed with
    the DB delete even if S3 is flaky.
    """
    success = 0
    for bucket, key in keys:
        try:
            await delete_object(bucket=bucket, key=key)
            success += 1
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "deletion_s3_object_failed",
                bucket=bucket,
                key=key,
                error=str(exc),
            )
    return success


async def _collect_user_s3_keys(db: AsyncSession, *, user_id: uuid.UUID) -> list[tuple[str, str]]:
    """Return every (bucket, key) tuple the user owns across S3."""
    settings = get_settings()
    sync_keys = (
        (await db.execute(select(SyncBlob.s3_object_key).where(SyncBlob.user_id == user_id)))
        .scalars()
        .all()
    )
    bio_keys = (
        (
            await db.execute(
                select(RawBiosignalUpload.s3_object_key).where(
                    RawBiosignalUpload.user_id == user_id
                )
            )
        )
        .scalars()
        .all()
    )
    return [
        *((settings.s3_bucket_sync, k) for k in sync_keys),
        *((settings.s3_bucket_biosignals, k) for k in bio_keys),
    ]
