"""NotificationService routing logic."""

from __future__ import annotations

import uuid
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.websocket_connection import WebsocketConnection
from app.schemas.realtime import OutboundMessage
from app.services.notifications import NotificationService


def _msg() -> OutboundMessage:
    return OutboundMessage(type="events.created", data={"id": str(uuid.uuid4())})


@pytest.mark.asyncio
async def test_notify_uses_websocket_when_local_connection_exists(
    db_session: AsyncSession,
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    fake_manager = AsyncMock()
    fake_manager.broadcast_to_user = AsyncMock(return_value=2)
    with (
        patch("app.services.notifications.manager", fake_manager),
        patch("app.services.notifications.send_to_user", AsyncMock()) as mock_fcm,
    ):
        svc = NotificationService()
        result = await svc.notify_user(db_session, user_id=user.id, message=_msg())
    assert result.delivered_via_websocket == 2
    assert result.delivered_via_fcm == 0
    mock_fcm.assert_not_called()


@pytest.mark.asyncio
async def test_notify_uses_fcm_when_no_websockets(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    fake_manager = AsyncMock()
    fake_manager.broadcast_to_user = AsyncMock(return_value=0)
    fake_fcm = AsyncMock(return_value=1)
    with (
        patch("app.services.notifications.manager", fake_manager),
        patch("app.services.notifications.send_to_user", fake_fcm),
    ):
        svc = NotificationService()
        result = await svc.notify_user(db_session, user_id=user.id, message=_msg())
    assert result.delivered_via_websocket == 0
    assert result.delivered_via_fcm == 1
    fake_fcm.assert_awaited_once()


@pytest.mark.asyncio
async def test_notify_falls_back_to_fcm_for_other_task_connections(
    db_session: AsyncSession,
) -> None:
    """User has a WS connection on task-other; we're task-mine. Should FCM."""
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()
    db_session.add(WebsocketConnection(user_id=user.id, task_id="task-other"))
    await db_session.flush()

    fake_manager = AsyncMock()
    fake_manager.broadcast_to_user = AsyncMock(return_value=0)
    fake_fcm = AsyncMock(return_value=1)
    with (
        patch("app.services.notifications.manager", fake_manager),
        patch("app.services.notifications.send_to_user", fake_fcm),
    ):
        svc = NotificationService()
        result = await svc.notify_user(db_session, user_id=user.id, message=_msg())
    assert result.delivered_via_fcm == 1


@pytest.mark.asyncio
async def test_notify_swallows_send_failures(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    fake_manager = AsyncMock()
    fake_manager.broadcast_to_user = AsyncMock(side_effect=RuntimeError("boom"))
    with (
        patch("app.services.notifications.manager", fake_manager),
        patch("app.services.notifications.send_to_user", AsyncMock(return_value=0)),
    ):
        svc = NotificationService()
        # Must NOT raise — caller (REST handler) must not fail because of push.
        result = await svc.notify_user(db_session, user_id=user.id, message=_msg())
    assert result.delivered_via_websocket == 0
    assert result.delivered_via_fcm == 0
