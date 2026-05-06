"""ensure_user_settings — idempotent default settings creation."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_settings import UserSettings
from app.services.user_settings import ensure_user_settings


@pytest.mark.asyncio
async def test_creates_settings_row_when_missing(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    settings = await ensure_user_settings(db_session, user)
    assert settings.user_id == user.id
    assert settings.notification_max_per_day == 5
    assert settings.stress_threshold == 0.75
    assert settings.language == "ko"


@pytest.mark.asyncio
async def test_returns_existing_when_present(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    pre = UserSettings(user_id=user.id, language="en")
    db_session.add(pre)
    await db_session.flush()

    settings = await ensure_user_settings(db_session, user)
    assert settings.language == "en"


@pytest.mark.asyncio
async def test_calling_twice_is_idempotent(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    s1 = await ensure_user_settings(db_session, user)
    s2 = await ensure_user_settings(db_session, user)
    assert s1.user_id == s2.user_id

    rows = (
        (await db_session.execute(select(UserSettings).where(UserSettings.user_id == user.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
