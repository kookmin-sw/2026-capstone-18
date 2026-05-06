"""Connection registry cleanup helpers.

`clear_task_connections` runs at app startup so a restarting ECS task doesn't
leave behind stale rows from its previous incarnation.

`sweep_stale_connections` is invoked periodically — Sprint 5 runs it from an
in-process loop; Sprint 7 will replace it with EventBridge.
"""

from __future__ import annotations

from datetime import UTC, datetime, timedelta

import structlog
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.websocket_connection import WebsocketConnection

logger = structlog.get_logger(__name__)


async def clear_task_connections(db: AsyncSession, *, task_id: str) -> int:
    """Delete every row tagged with `task_id`. Returns count deleted."""
    result = await db.execute(
        delete(WebsocketConnection).where(WebsocketConnection.task_id == task_id)
    )
    await db.flush()
    deleted = int(getattr(result, "rowcount", 0) or 0)
    if deleted:
        logger.info("websocket_task_rows_cleared", task_id=task_id, count=deleted)
    return deleted


async def sweep_stale_connections(db: AsyncSession, *, idle_timeout_seconds: int) -> int:
    """Delete rows whose last_seen_at is older than `idle_timeout_seconds`."""
    cutoff = datetime.now(tz=UTC) - timedelta(seconds=idle_timeout_seconds)
    count_result = await db.execute(
        select(func.count())
        .select_from(WebsocketConnection)
        .where(WebsocketConnection.last_seen_at < cutoff)
    )
    count = int(count_result.scalar() or 0)
    if count == 0:
        return 0
    await db.execute(delete(WebsocketConnection).where(WebsocketConnection.last_seen_at < cutoff))
    await db.flush()
    logger.info("websocket_stale_swept", count=count, cutoff=cutoff.isoformat())
    return count
