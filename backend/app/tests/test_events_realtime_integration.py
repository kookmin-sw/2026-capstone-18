"""End-to-end: REST event create -> WS broadcast."""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.dependencies import get_db
from app.main import app
from app.models.user import User


@pytest.mark.asyncio
async def test_event_creation_pushes_via_websocket(
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
        token = make_jwt(sub=str(sub))
        # Use httpx-ws to share the event loop with the test (matches Task 5 test pattern)
        from httpx import AsyncClient
        from httpx_ws import AsyncWebSocketSession, aconnect_ws
        from httpx_ws.transport import ASGIWebSocketTransport

        ws: AsyncWebSocketSession
        async with (
            AsyncClient(
                transport=ASGIWebSocketTransport(app=app),
                base_url="http://test",
            ) as http,
            aconnect_ws(f"http://test/ws/realtime?token={token}", http) as ws,
        ):
            await ws.receive_json()  # discard hello

            resp = await http.post(
                "/api/v1/events",
                headers={"Authorization": f"Bearer {token}"},
                json={"detected_at": "2026-05-06T12:00:00+00:00"},
            )
            assert resp.status_code == 201

            msg = await ws.receive_json()
            assert msg["type"] == "events.created"
            assert "id" in msg["data"]
    finally:
        app.dependency_overrides.clear()
