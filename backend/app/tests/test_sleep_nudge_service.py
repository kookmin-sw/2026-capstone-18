"""Unit tests for the sleep-nudge sender."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.sleep_log import SleepLog
from app.models.user_settings import UserSettings


def _yesterday_utc() -> date:
    return (datetime.now(tz=UTC) - timedelta(days=1)).date()


@pytest.mark.asyncio
async def test_send_returns_zero_when_no_users(
    db_session: AsyncSession,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    result = await send_sleep_nudges(db_session, fcm_sender=_StubSender())
    assert result.candidates == 0
    assert result.sent == 0


@pytest.mark.asyncio
async def test_send_skips_user_who_already_logged_last_night(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(
        FcmToken(
            user_id=me.id,
            token="dev-token-1",
            platform="android",
        )
    )
    db_session.add(
        SleepLog(
            id=uuid.uuid4(),
            user_id=me.id,
            fell_asleep_at=datetime.now(tz=UTC) - timedelta(hours=10),
            woke_up_at=datetime.now(tz=UTC) - timedelta(hours=2),
            ended_on=_yesterday_utc(),
            rating="okay",
        )
    )
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)

    assert result.candidates == 1
    assert result.sent == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_sends_to_user_who_missed_last_night(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(
        FcmToken(
            user_id=me.id,
            token="dev-token-1",
            platform="android",
        )
    )
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)

    assert result.candidates == 1
    assert result.sent == 1
    assert sender.calls == [me.id]


@pytest.mark.asyncio
async def test_send_skips_opted_out_users(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=False))
    db_session.add(FcmToken(user_id=me.id, token="t", platform="android"))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_skips_users_with_no_fcm_token(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_skips_deleted_users(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user(deleted_at=datetime.now(tz=UTC))
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(FcmToken(user_id=me.id, token="t", platform="android"))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


class _StubSender:
    def __init__(self) -> None:
        self.calls: list[uuid.UUID] = []

    async def __call__(
        self, db: AsyncSession, *, user_id: uuid.UUID, payload: dict[str, str]
    ) -> int:
        self.calls.append(user_id)
        return 1
