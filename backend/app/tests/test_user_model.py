"""User model tests — fields, defaults, and the UserSettings relationship."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_settings import UserSettings


@pytest.mark.asyncio
async def test_user_defaults_to_anonymous(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    assert user.id is not None
    assert user.supabase_user_id is None
    assert user.anon_id is not None
    assert user.role == "user"
    assert user.consent_raw_biosignals is False
    assert user.consent_revoked_at is None
    assert user.deleted_at is None
    assert isinstance(user.created_at, datetime)


@pytest.mark.asyncio
async def test_user_can_be_promoted_with_supabase_id(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4(), supabase_user_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    assert user.supabase_user_id is not None


@pytest.mark.asyncio
async def test_user_settings_relationship_is_configured(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    settings_row = UserSettings(user_id=user.id)
    db_session.add(settings_row)
    await db_session.flush()

    refreshed = (await db_session.execute(select(User).where(User.id == user.id))).scalar_one()
    await db_session.refresh(refreshed, attribute_names=["settings"])
    assert refreshed.settings is not None
    assert refreshed.settings.notification_max_per_day == 5
    assert refreshed.settings.stress_threshold == pytest.approx(0.75)
    assert refreshed.settings.language == "ko"


@pytest.mark.asyncio
async def test_deleted_at_marks_user_as_pending_deletion(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    user.deleted_at = datetime.now(tz=UTC)
    await db_session.flush()

    assert user.deleted_at is not None


@pytest.mark.asyncio
async def test_anon_id_is_unique_across_users(db_session: AsyncSession) -> None:
    shared_anon_id = uuid.uuid4()
    db_session.add(User(anon_id=shared_anon_id))
    await db_session.flush()

    # Wrap the conflicting insert in a SAVEPOINT so the IntegrityError only rolls back
    # the savepoint, leaving the outer per-test transaction intact for teardown.
    async with db_session.begin_nested():
        db_session.add(User(anon_id=shared_anon_id))
        with pytest.raises(IntegrityError):
            await db_session.flush()


@pytest.mark.asyncio
async def test_supabase_user_id_is_unique_across_users(db_session: AsyncSession) -> None:
    shared_supabase_id = uuid.uuid4()
    db_session.add(User(supabase_user_id=shared_supabase_id, anon_id=uuid.uuid4()))
    await db_session.flush()

    async with db_session.begin_nested():
        db_session.add(User(supabase_user_id=shared_supabase_id, anon_id=uuid.uuid4()))
        with pytest.raises(IntegrityError):
            await db_session.flush()
