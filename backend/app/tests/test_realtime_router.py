"""WebSocket /ws/realtime endpoint.

Uses httpx-ws's ASGIWebSocketTransport so the FastAPI app runs on the SAME
event loop as the test. Starlette's sync TestClient spawns a separate
thread/loop for the ASGI app, which conflicts with asyncpg connections owned
by the test loop ("another operation in progress"). Running everything on one
loop avoids that.
"""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from typing import Any

import httpx
import pytest
from httpx_ws import AsyncWebSocketSession, WebSocketDisconnect, aconnect_ws
from httpx_ws.transport import ASGIWebSocketTransport
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.dependencies import get_db
from app.main import app
from app.models.user import User
from app.models.websocket_connection import WebsocketConnection


@pytest.mark.asyncio
async def test_ws_rejects_missing_token(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGIWebSocketTransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            with pytest.raises(WebSocketDisconnect) as exc:
                async with aconnect_ws("http://test/ws/realtime", client=client):
                    pass
            assert exc.value.code == 1008
    finally:
        app.dependency_overrides.clear()


@pytest.mark.asyncio
async def test_ws_rejects_invalid_token(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGIWebSocketTransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            with pytest.raises(WebSocketDisconnect) as exc:
                async with aconnect_ws("http://test/ws/realtime?token=garbage", client=client):
                    pass
            assert exc.value.code == 1008
    finally:
        app.dependency_overrides.clear()


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
        transport = ASGIWebSocketTransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            token = make_jwt(sub=str(sub))
            ws: AsyncWebSocketSession
            async with aconnect_ws(f"http://test/ws/realtime?token={token}", client=client) as ws:
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
        transport = ASGIWebSocketTransport(app=app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
            token = make_jwt(sub=str(sub))
            ws: AsyncWebSocketSession
            async with aconnect_ws(f"http://test/ws/realtime?token={token}", client=client) as ws:
                await ws.receive_json()  # discard the hello
                await ws.send_json({"type": "ping"})
                pong = await ws.receive_json()
                assert pong["type"] == "system.heartbeat"
    finally:
        app.dependency_overrides.clear()
