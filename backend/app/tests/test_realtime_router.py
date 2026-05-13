"""WebSocket /ws/realtime endpoint tests.

Rejection tests (invalid/missing auth) use a mocked WebSocket so they are
fast and do not depend on httpx-ws behaviour around server-initiated closes.

Happy-path tests (valid token, ping/pong) use httpx-ws ASGIWebSocketTransport
so the FastAPI app runs on the same event loop as the test — avoiding the
asyncpg "another operation in progress" error that Starlette's sync
TestClient causes.

Auth is now delivered as the first message payload {type: "auth", token: ...},
NOT as a query parameter.
"""

from __future__ import annotations

import asyncio
import uuid
from collections.abc import AsyncGenerator
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import httpx
import pytest
from fastapi import status
from httpx_ws import AsyncWebSocketSession, aconnect_ws
from httpx_ws.transport import ASGIWebSocketTransport
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.dependencies import get_db
from app.main import app
from app.models.user import User
from app.models.websocket_connection import WebsocketConnection
from app.realtime.router import ws_realtime

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def _make_mock_ws() -> MagicMock:
    """Return a MagicMock with async accept/close methods."""
    ws = MagicMock()
    ws.accept = AsyncMock()
    ws.close = AsyncMock()
    return ws


def _make_client_and_transport() -> tuple[ASGIWebSocketTransport, httpx.AsyncClient]:
    transport = ASGIWebSocketTransport(app=app)
    client = httpx.AsyncClient(transport=transport, base_url="http://test")
    return transport, client


# ---------------------------------------------------------------------------
# Rejection tests — unit-level (no ASGI stack needed)
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_ws_rejects_auth_timeout(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    """Closes with 1008 when no auth message arrives within the timeout."""
    ws = _make_mock_ws()
    with patch(
        "app.realtime.router.asyncio.wait_for",
        new=AsyncMock(side_effect=asyncio.TimeoutError),
    ):
        await ws_realtime(websocket=ws, db=db_session)

    ws.accept.assert_called_once()
    ws.close.assert_called_once_with(code=status.WS_1008_POLICY_VIOLATION)


@pytest.mark.asyncio
async def test_ws_rejects_wrong_message_type(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    """Closes with 1008 when first message type is not 'auth'."""
    ws = _make_mock_ws()
    ws.receive_json = AsyncMock(return_value={"type": "ping", "token": "whatever"})

    await ws_realtime(websocket=ws, db=db_session)

    ws.accept.assert_called_once()
    ws.close.assert_called_once_with(code=status.WS_1008_POLICY_VIOLATION)


@pytest.mark.asyncio
async def test_ws_rejects_auth_message_without_token(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    """Closes with 1008 when auth message has no 'token' field."""
    ws = _make_mock_ws()
    ws.receive_json = AsyncMock(return_value={"type": "auth"})

    await ws_realtime(websocket=ws, db=db_session)

    ws.accept.assert_called_once()
    ws.close.assert_called_once_with(code=status.WS_1008_POLICY_VIOLATION)


@pytest.mark.asyncio
async def test_ws_rejects_invalid_token(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    """Closes with 1008 when token verification fails."""
    ws = _make_mock_ws()
    ws.receive_json = AsyncMock(return_value={"type": "auth", "token": "garbage"})

    await ws_realtime(websocket=ws, db=db_session)

    ws.accept.assert_called_once()
    ws.close.assert_called_once_with(code=status.WS_1008_POLICY_VIOLATION)


# ---------------------------------------------------------------------------
# Happy-path tests — integration via ASGI transport
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_ws_accepts_valid_token_and_registers_connection(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    sub = uuid.uuid4()
    user = User(supabase_user_id=sub, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        _, client = _make_client_and_transport()
        async with client:
            token = make_jwt(sub=str(sub))
            ws: AsyncWebSocketSession
            async with aconnect_ws("http://test/ws/realtime", client=client) as ws:
                await ws.send_json({"type": "auth", "token": token})
                hello = await ws.receive_json()
                assert hello["type"] == "system.heartbeat"

                rows = (
                    (
                        await db_session.execute(
                            select(WebsocketConnection).where(
                                WebsocketConnection.user_id == user.id
                            )
                        )
                    )
                    .scalars()
                    .all()
                )
                assert len(rows) == 1
        rows_after = (
            (
                await db_session.execute(
                    select(WebsocketConnection).where(WebsocketConnection.user_id == user.id)
                )
            )
            .scalars()
            .all()
        )
        assert rows_after == []
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_ws_responds_to_client_ping_with_pong(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    sub = uuid.uuid4()
    user = User(supabase_user_id=sub, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        _, client = _make_client_and_transport()
        async with client:
            token = make_jwt(sub=str(sub))
            ws: AsyncWebSocketSession
            async with aconnect_ws("http://test/ws/realtime", client=client) as ws:
                await ws.send_json({"type": "auth", "token": token})
                await ws.receive_json()  # discard the hello
                await ws.send_json({"type": "ping"})
                pong = await ws.receive_json()
                assert pong["type"] == "system.heartbeat"
    finally:
        app.dependency_overrides.clear()
