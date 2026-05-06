"""Tests for app.services.deletion."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.raw_biosignal_upload import RawBiosignalUpload
from app.models.sync_blob import SyncBlob
from app.models.user import User
from app.services.deletion import _collect_user_s3_keys


@pytest.mark.asyncio
async def test_collect_user_s3_keys_returns_sync_and_biosignal_keys(
    db_session: AsyncSession,
) -> None:
    settings = get_settings()
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    db_session.add_all(
        [
            SyncBlob(
                user_id=user.id,
                s3_object_key=f"users/{user.id}/backup/aaa.bin",
                kind="backup",
                byte_size=10,
            ),
            RawBiosignalUpload(
                user_id=user.id,
                s3_object_key=f"users/{user.id}/biosignals/hrv/bbb.bin",
                signal_type="hrv",
                recorded_at=datetime.now(tz=UTC),
            ),
        ]
    )
    await db_session.flush()

    keys = await _collect_user_s3_keys(db_session, user_id=user.id)

    assert (settings.s3_bucket_sync, f"users/{user.id}/backup/aaa.bin") in keys
    assert (
        settings.s3_bucket_biosignals,
        f"users/{user.id}/biosignals/hrv/bbb.bin",
    ) in keys
    assert len(keys) == 2
