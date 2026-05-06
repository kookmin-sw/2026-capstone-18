"""RawBiosignalUpload ORM model basics."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.raw_biosignal_upload import RawBiosignalUpload
from app.models.user import User


@pytest.mark.asyncio
async def test_raw_biosignal_upload_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    upload = RawBiosignalUpload(
        user_id=user.id,
        s3_object_key=f"users/{user.id}/biosignals/abc.bin",
        signal_type="hrv",
        recorded_at=datetime(2026, 5, 6, 12, tzinfo=UTC),
        expires_at=datetime(2026, 5, 6, 12, tzinfo=UTC) + timedelta(days=365),
    )
    db_session.add(upload)
    await db_session.flush()

    fetched = (
        await db_session.execute(
            select(RawBiosignalUpload).where(RawBiosignalUpload.id == upload.id)
        )
    ).scalar_one()
    assert fetched.signal_type == "hrv"
    assert fetched.user_id == user.id
