"""Connection registry — DB-level helpers for the websocket_connections table.

These functions take an AsyncSession and rely on the caller's request boundary
to commit (matches `get_db`'s auto-commit pattern from Sprint 3).
"""

from __future__ import annotations

import uuid
from collections.abc import Sequence
from datetime import UTC, datetime

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.websocket_connection import WebsocketConnection


async def register(db: AsyncSession, *, user_id: uuid.UUID, task_id: str) -> uuid.UUID:
    """Insert a new connection row, return its id."""
    conn = WebsocketConnection(user_id=user_id, task_id=task_id)
    db.add(conn)
    await db.flush()
    return conn.id


async def unregister(db: AsyncSession, *, connection_id: uuid.UUID) -> None:
    """Delete a connection row. Idempotent — no error if already gone."""
    await db.execute(delete(WebsocketConnection).where(WebsocketConnection.id == connection_id))
    await db.flush()


async def touch_heartbeat(db: AsyncSession, *, connection_id: uuid.UUID) -> None:
    """Set last_seen_at to now for one connection."""
    row = (
        await db.execute(select(WebsocketConnection).where(WebsocketConnection.id == connection_id))
    ).scalar_one_or_none()
    if row is not None:
        row.last_seen_at = datetime.now(tz=UTC)
        await db.flush()


async def list_for_user(db: AsyncSession, *, user_id: uuid.UUID) -> Sequence[WebsocketConnection]:
    return (
        (
            await db.execute(
                select(WebsocketConnection).where(WebsocketConnection.user_id == user_id)
            )
        )
        .scalars()
        .all()
    )


async def list_for_task(db: AsyncSession, *, task_id: str) -> Sequence[WebsocketConnection]:
    return (
        (
            await db.execute(
                select(WebsocketConnection).where(WebsocketConnection.task_id == task_id)
            )
        )
        .scalars()
        .all()
    )
