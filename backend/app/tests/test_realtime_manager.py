"""ConnectionManager in-process broadcast."""

from __future__ import annotations

import uuid
from typing import Any
from unittest.mock import AsyncMock

import pytest

from app.realtime.manager import ConnectionManager
from app.schemas.realtime import OutboundMessage


def _outbound() -> OutboundMessage:
    return OutboundMessage(type="events.created", data={"id": str(uuid.uuid4())})


@pytest.mark.asyncio
async def test_attach_and_detach_track_connections() -> None:
    mgr = ConnectionManager()
    user_id = uuid.uuid4()
    conn_id = uuid.uuid4()
    ws: Any = AsyncMock()

    mgr.attach(connection_id=conn_id, user_id=user_id, websocket=ws)
    assert mgr.has_local_connections(user_id) is True

    mgr.detach(connection_id=conn_id)
    assert mgr.has_local_connections(user_id) is False


@pytest.mark.asyncio
async def test_broadcast_to_user_writes_to_all_their_local_websockets() -> None:
    mgr = ConnectionManager()
    user_id = uuid.uuid4()
    ws_a: Any = AsyncMock()
    ws_b: Any = AsyncMock()
    other_ws: Any = AsyncMock()

    mgr.attach(connection_id=uuid.uuid4(), user_id=user_id, websocket=ws_a)
    mgr.attach(connection_id=uuid.uuid4(), user_id=user_id, websocket=ws_b)
    mgr.attach(connection_id=uuid.uuid4(), user_id=uuid.uuid4(), websocket=other_ws)

    msg = _outbound()
    delivered = await mgr.broadcast_to_user(user_id, msg)
    assert delivered == 2
    ws_a.send_json.assert_awaited_once()
    ws_b.send_json.assert_awaited_once()
    other_ws.send_json.assert_not_called()


@pytest.mark.asyncio
async def test_broadcast_to_user_returns_zero_when_no_local_connections() -> None:
    mgr = ConnectionManager()
    msg = _outbound()
    delivered = await mgr.broadcast_to_user(uuid.uuid4(), msg)
    assert delivered == 0


@pytest.mark.asyncio
async def test_broadcast_swallows_send_failure_and_detaches() -> None:
    mgr = ConnectionManager()
    user_id = uuid.uuid4()
    conn_id = uuid.uuid4()
    bad_ws: Any = AsyncMock()
    bad_ws.send_json.side_effect = RuntimeError("connection closed")

    mgr.attach(connection_id=conn_id, user_id=user_id, websocket=bad_ws)
    msg = _outbound()
    delivered = await mgr.broadcast_to_user(user_id, msg)
    assert delivered == 0
    assert mgr.has_local_connections(user_id) is False


def test_outbound_message_serializes_with_iso_ts() -> None:
    msg = OutboundMessage(type="events.created", data={"foo": "bar"})
    payload = msg.model_dump()
    assert payload["type"] == "events.created"
    assert payload["data"] == {"foo": "bar"}
    assert isinstance(payload["ts"], str)
    assert "T" in payload["ts"]
