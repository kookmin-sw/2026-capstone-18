"""Connection registry helpers."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.websocket_connection import WebsocketConnection
from app.realtime.registry import (
    list_for_task,
    list_for_user,
    register,
    touch_heartbeat,
    unregister,
)


@pytest.mark.asyncio
async def test_register_creates_a_row(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    conn_id = await register(db_session, user_id=user.id, task_id="task-a")
    assert isinstance(conn_id, uuid.UUID)

    rows = (await db_session.execute(select(WebsocketConnection))).scalars().all()
    assert len(rows) == 1
    assert rows[0].id == conn_id
    assert rows[0].task_id == "task-a"


@pytest.mark.asyncio
async def test_unregister_deletes_the_row(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    conn_id = await register(db_session, user_id=user.id, task_id="task-a")
    await unregister(db_session, connection_id=conn_id)

    rows = (await db_session.execute(select(WebsocketConnection))).scalars().all()
    assert rows == []


@pytest.mark.asyncio
async def test_touch_heartbeat_updates_last_seen(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    conn_id = await register(db_session, user_id=user.id, task_id="task-a")
    # Force last_seen into the past
    row = (
        await db_session.execute(
            select(WebsocketConnection).where(WebsocketConnection.id == conn_id)
        )
    ).scalar_one()
    row.last_seen_at = datetime.now(tz=UTC) - timedelta(minutes=10)
    await db_session.flush()

    await touch_heartbeat(db_session, connection_id=conn_id)
    refreshed = (
        await db_session.execute(
            select(WebsocketConnection).where(WebsocketConnection.id == conn_id)
        )
    ).scalar_one()
    assert (datetime.now(tz=UTC) - refreshed.last_seen_at).total_seconds() < 5


@pytest.mark.asyncio
async def test_list_for_user_returns_only_their_connections(
    db_session: AsyncSession,
) -> None:
    me = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    other = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add_all([me, other])
    await db_session.flush()

    mine_a = await register(db_session, user_id=me.id, task_id="task-1")
    mine_b = await register(db_session, user_id=me.id, task_id="task-2")
    await register(db_session, user_id=other.id, task_id="task-1")

    mine = await list_for_user(db_session, user_id=me.id)
    assert {c.id for c in mine} == {mine_a, mine_b}


@pytest.mark.asyncio
async def test_list_for_task_returns_only_that_tasks_rows(
    db_session: AsyncSession,
) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    on_task_a = await register(db_session, user_id=user.id, task_id="task-a")
    await register(db_session, user_id=user.id, task_id="task-b")

    rows = await list_for_task(db_session, task_id="task-a")
    assert {r.id for r in rows} == {on_task_a}
