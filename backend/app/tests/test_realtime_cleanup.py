"""Stale-connection cleanup."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.websocket_connection import WebsocketConnection
from app.realtime.cleanup import clear_task_connections, sweep_stale_connections


@pytest.mark.asyncio
async def test_clear_task_connections_only_removes_that_task(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    db_session.add_all(
        [
            WebsocketConnection(user_id=user.id, task_id="task-old"),
            WebsocketConnection(user_id=user.id, task_id="task-new"),
        ]
    )
    await db_session.flush()

    await clear_task_connections(db_session, task_id="task-old")
    rows = (await db_session.execute(select(WebsocketConnection))).scalars().all()
    assert [r.task_id for r in rows] == ["task-new"]


@pytest.mark.asyncio
async def test_sweep_stale_deletes_rows_past_timeout(db_session: AsyncSession) -> None:
    user = User(supabase_user_id=uuid.uuid4(), anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    fresh = WebsocketConnection(user_id=user.id, task_id="task-a")
    stale = WebsocketConnection(
        user_id=user.id,
        task_id="task-a",
        last_seen_at=datetime.now(tz=UTC) - timedelta(seconds=600),
    )
    db_session.add_all([fresh, stale])
    await db_session.flush()

    purged = await sweep_stale_connections(db_session, idle_timeout_seconds=300)
    assert purged == 1
    rows = (await db_session.execute(select(WebsocketConnection))).scalars().all()
    assert {r.id for r in rows} == {fresh.id}
