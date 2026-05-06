"""FCM service: init + send_to_user."""

from __future__ import annotations

import uuid
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.user import User
from app.services.fcm import init_firebase, send_to_user


def test_init_firebase_is_idempotent_when_no_creds(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(
        "app.services.fcm.get_settings",
        lambda: MagicMock(firebase_credentials_json=None),
    )
    init_firebase()
    init_firebase()


@pytest.mark.asyncio
async def test_send_to_user_skips_when_user_has_no_tokens(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    sent = await send_to_user(db_session, user_id=user.id, payload={"foo": "bar"})
    assert sent == 0


@pytest.mark.asyncio
async def test_send_to_user_calls_firebase_for_each_token(
    db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    db_session.add_all(
        [
            FcmToken(user_id=user.id, token="t1", platform="android"),
            FcmToken(user_id=user.id, token="t2", platform="android"),
        ]
    )
    await db_session.flush()

    fake_response = MagicMock()
    fake_response.responses = [
        MagicMock(success=True, exception=None),
        MagicMock(success=True, exception=None),
    ]
    fake_response.success_count = 2
    fake_response.failure_count = 0

    with patch(
        "app.services.fcm._firebase_send_multicast", return_value=fake_response
    ) as mock_send:
        sent = await send_to_user(db_session, user_id=user.id, payload={"x": 1})
    assert sent == 2
    mock_send.assert_called_once()
    args, _ = mock_send.call_args
    multicast = args[0]
    assert sorted(multicast.tokens) == ["t1", "t2"]


@pytest.mark.asyncio
async def test_send_to_user_deletes_unregistered_tokens(
    db_session: AsyncSession,
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    db_session.add_all(
        [
            FcmToken(user_id=user.id, token="good", platform="android"),
            FcmToken(user_id=user.id, token="dead", platform="android"),
        ]
    )
    await db_session.flush()

    bad_exc: Any = MagicMock()
    bad_exc.code = "UNREGISTERED"
    fake_response = MagicMock()
    fake_response.responses = [
        MagicMock(success=True, exception=None),
        MagicMock(success=False, exception=bad_exc),
    ]
    fake_response.success_count = 1
    fake_response.failure_count = 1

    with patch("app.services.fcm._firebase_send_multicast", return_value=fake_response):
        sent = await send_to_user(db_session, user_id=user.id, payload={"x": 1})
    assert sent == 1
    surviving = (
        (await db_session.execute(select(FcmToken).where(FcmToken.user_id == user.id)))
        .scalars()
        .all()
    )
    assert {t.token for t in surviving} == {"good"}
