"""UserSettings model tests — defaults match spec §6.3."""

from __future__ import annotations

import uuid
from datetime import time

import pytest
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_settings import UserSettings


@pytest.mark.asyncio
async def test_user_settings_default_values(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    s = UserSettings(user_id=user.id)
    db_session.add(s)
    await db_session.flush()
    await db_session.refresh(s)

    assert s.notification_max_per_day == 5
    assert s.stress_threshold == pytest.approx(0.75)
    assert s.quiet_hours_start == time(22, 0)
    assert s.quiet_hours_end == time(8, 0)
    assert s.silence_during_meeting is True
    assert s.silence_during_exercise is True
    assert s.consent_audit_logging is True
    assert s.language == "ko"


@pytest.mark.asyncio
async def test_user_settings_user_id_is_primary_key(db_session: AsyncSession) -> None:
    """A second UserSettings row for the same user_id must violate the PK.

    The duplicate insert is wrapped in a SAVEPOINT (`begin_nested`) so the
    IntegrityError only rolls back the savepoint — the outer per-test
    transaction stays usable for teardown.
    """
    user = User(anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    db_session.add(UserSettings(user_id=user.id))
    await db_session.flush()

    with pytest.raises(IntegrityError):
        async with db_session.begin_nested():
            db_session.add(UserSettings(user_id=user.id))
            await db_session.flush()
