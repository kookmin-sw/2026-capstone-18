"""SyncBlob ORM model basics."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sync_blob import SyncBlob
from app.models.user import User


@pytest.mark.asyncio
async def test_sync_blob_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    blob = SyncBlob(
        user_id=user.id,
        s3_object_key=f"users/{user.id}/backup-2026-05-06.bin",
        kind="backup",
        byte_size=1024,
    )
    db_session.add(blob)
    await db_session.flush()

    fetched = (
        await db_session.execute(select(SyncBlob).where(SyncBlob.id == blob.id))
    ).scalar_one()
    assert fetched.user_id == user.id
    assert fetched.kind == "backup"
    assert fetched.byte_size == 1024
