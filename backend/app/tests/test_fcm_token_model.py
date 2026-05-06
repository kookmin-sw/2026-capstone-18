"""FcmToken ORM model basics."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.user import User


@pytest.mark.asyncio
async def test_fcm_token_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    tok = FcmToken(user_id=user.id, token="fake-token-abc", platform="android")
    db_session.add(tok)
    await db_session.flush()

    fetched = (
        await db_session.execute(select(FcmToken).where(FcmToken.token == "fake-token-abc"))
    ).scalar_one()
    assert fetched.user_id == user.id
    assert fetched.platform == "android"
    assert fetched.last_seen_at is not None


@pytest.mark.asyncio
async def test_fcm_token_user_token_pair_is_unique(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    db_session.add(FcmToken(user_id=user.id, token="dup", platform="android"))
    await db_session.flush()

    db_session.add(FcmToken(user_id=user.id, token="dup", platform="android"))
    with pytest.raises(IntegrityError):
        await db_session.flush()
    await db_session.rollback()
