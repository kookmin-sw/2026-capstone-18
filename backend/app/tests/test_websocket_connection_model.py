"""WebsocketConnection ORM model basics."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.websocket_connection import WebsocketConnection


@pytest.mark.asyncio
async def test_websocket_connection_inserts_and_round_trips(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    conn = WebsocketConnection(
        user_id=user.id,
        task_id="task-arn-abc",
        connected_at=datetime(2026, 5, 6, 12, 0, tzinfo=UTC),
        last_seen_at=datetime(2026, 5, 6, 12, 0, tzinfo=UTC),
    )
    db_session.add(conn)
    await db_session.flush()

    fetched = (
        await db_session.execute(
            select(WebsocketConnection).where(WebsocketConnection.id == conn.id)
        )
    ).scalar_one()
    assert fetched.user_id == user.id
    assert fetched.task_id == "task-arn-abc"
    assert fetched.last_seen_at == datetime(2026, 5, 6, 12, 0, tzinfo=UTC)


@pytest.mark.asyncio
async def test_websocket_connection_default_id_is_uuid(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    conn = WebsocketConnection(
        user_id=user.id,
        task_id="task-x",
        connected_at=datetime.now(tz=UTC),
        last_seen_at=datetime.now(tz=UTC),
    )
    db_session.add(conn)
    await db_session.flush()
    assert isinstance(conn.id, uuid.UUID)
