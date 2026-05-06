"""FCM service: init + send_to_user."""

from __future__ import annotations

import json
import uuid
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

import app.services.fcm as fcm_module
from app.models.fcm_token import FcmToken
from app.models.user import User
from app.services.fcm import init_firebase, send_to_user


def test_init_firebase_is_idempotent_when_no_creds(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fcm_module, "_initialized", False)
    monkeypatch.setattr(
        "app.services.fcm.get_settings",
        lambda: MagicMock(firebase_credentials_json=None),
    )
    init_firebase()
    init_firebase()


def test_init_firebase_initializes_with_creds(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fcm_module, "_initialized", False)
    fake_creds_json = json.dumps({"type": "service_account", "project_id": "p"})
    monkeypatch.setattr(
        "app.services.fcm.get_settings",
        lambda: MagicMock(firebase_credentials_json=fake_creds_json),
    )

    import firebase_admin
    from firebase_admin import credentials as credentials_mod

    fake_cred_obj = MagicMock()
    monkeypatch.setattr(credentials_mod, "Certificate", MagicMock(return_value=fake_cred_obj))
    init_app_mock = MagicMock()
    monkeypatch.setattr(firebase_admin, "initialize_app", init_app_mock)

    init_firebase()

    init_app_mock.assert_called_once_with(fake_cred_obj)


def test_init_firebase_swallows_errors(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(fcm_module, "_initialized", False)
    monkeypatch.setattr(
        "app.services.fcm.get_settings",
        lambda: MagicMock(firebase_credentials_json="not-valid-json"),
    )
    # json.loads will raise — init should swallow and still mark initialized.
    init_firebase()
    assert fcm_module._initialized is True


def test_firebase_send_multicast_calls_messaging(monkeypatch: pytest.MonkeyPatch) -> None:
    from firebase_admin import messaging

    sent = MagicMock(return_value="ok")
    monkeypatch.setattr(messaging, "send_each_for_multicast", sent)

    result = fcm_module._firebase_send_multicast("multicast-arg")

    assert result == "ok"
    sent.assert_called_once_with("multicast-arg")


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
async def test_send_to_user_returns_zero_when_firebase_admin_missing(
    db_session: AsyncSession, monkeypatch: pytest.MonkeyPatch
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    db_session.add(FcmToken(user_id=user.id, token="t1", platform="android"))
    await db_session.flush()

    import builtins

    real_import = builtins.__import__

    def fake_import(name: str, *args: Any, **kwargs: Any) -> Any:
        if name == "firebase_admin" or name.startswith("firebase_admin."):
            raise ImportError("firebase_admin missing")
        return real_import(name, *args, **kwargs)

    monkeypatch.setattr(builtins, "__import__", fake_import)
    sent = await send_to_user(db_session, user_id=user.id, payload={"x": 1})
    assert sent == 0


@pytest.mark.asyncio
async def test_send_to_user_returns_zero_when_firebase_send_raises(
    db_session: AsyncSession,
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    db_session.add(FcmToken(user_id=user.id, token="t1", platform="android"))
    await db_session.flush()

    with patch(
        "app.services.fcm._firebase_send_multicast",
        side_effect=RuntimeError("network down"),
    ):
        sent = await send_to_user(db_session, user_id=user.id, payload={"x": 1})
    assert sent == 0


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
