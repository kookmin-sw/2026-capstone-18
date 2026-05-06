"""Tests for app.services.deletion."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

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


@pytest.mark.asyncio
async def test_delete_s3_keys_best_effort_deletes_each_key(s3_mock: Any) -> None:
    from app.services.deletion import _delete_s3_keys_best_effort

    s3_mock.put_object(Bucket="little-signals-sync-staging", Key="users/u1/backup/a.bin", Body=b"x")
    s3_mock.put_object(
        Bucket="little-signals-biosignals-staging",
        Key="users/u1/biosignals/hrv/b.bin",
        Body=b"y",
    )

    deleted = await _delete_s3_keys_best_effort(
        [
            ("little-signals-sync-staging", "users/u1/backup/a.bin"),
            ("little-signals-biosignals-staging", "users/u1/biosignals/hrv/b.bin"),
        ]
    )

    assert deleted == 2
    contents = s3_mock.list_objects_v2(Bucket="little-signals-sync-staging").get("Contents", [])
    assert contents == []


@pytest.mark.asyncio
async def test_delete_s3_keys_best_effort_swallows_errors(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    """A failing S3 delete logs a warning but does not raise."""
    from app.services import deletion as deletion_module
    from app.services.deletion import _delete_s3_keys_best_effort

    async def boom(*, bucket: str, key: str) -> None:
        raise RuntimeError(f"s3 down: {bucket}/{key}")

    monkeypatch.setattr(deletion_module, "delete_object", boom)

    deleted = await _delete_s3_keys_best_effort(
        [("any-bucket", "any-key"), ("any-bucket", "other-key")]
    )

    assert deleted == 0
