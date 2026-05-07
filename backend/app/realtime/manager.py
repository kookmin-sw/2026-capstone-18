"""In-process WebSocket connection manager.

Holds a singleton mapping of connection_id -> live WebSocket for THIS task.
The DB registry knows about connections across all tasks; the manager only
knows about connections in this process.
"""

from __future__ import annotations

import asyncio
import uuid
from typing import TYPE_CHECKING

import structlog

from app.observability.metrics import active_websocket_connections
from app.schemas.realtime import OutboundMessage

if TYPE_CHECKING:
    from fastapi import WebSocket

logger = structlog.get_logger(__name__)


class ConnectionManager:
    """Process-local registry of live WebSocket objects."""

    def __init__(self) -> None:
        # connection_id -> WebSocket
        self._sockets: dict[uuid.UUID, WebSocket] = {}
        # user_id -> set of connection_ids
        self._by_user: dict[uuid.UUID, set[uuid.UUID]] = {}
        # connection_id -> per-socket send lock (Starlette send is not concurrent-safe)
        self._locks: dict[uuid.UUID, asyncio.Lock] = {}

    def attach(
        self,
        *,
        connection_id: uuid.UUID,
        user_id: uuid.UUID,
        websocket: WebSocket,
    ) -> None:
        active_websocket_connections.inc()
        self._sockets[connection_id] = websocket
        self._by_user.setdefault(user_id, set()).add(connection_id)
        self._locks[connection_id] = asyncio.Lock()

    def detach(self, *, connection_id: uuid.UUID) -> None:
        ws = self._sockets.pop(connection_id, None)
        self._locks.pop(connection_id, None)
        if ws is None:
            return
        active_websocket_connections.dec()
        for user_id, ids in list(self._by_user.items()):
            if connection_id in ids:
                ids.discard(connection_id)
                if not ids:
                    del self._by_user[user_id]

    def has_local_connections(self, user_id: uuid.UUID) -> bool:
        return bool(self._by_user.get(user_id))

    async def broadcast_to_user(self, user_id: uuid.UUID, message: OutboundMessage) -> int:
        """Send `message` to every local WebSocket for `user_id`. Returns the
        number of successful sends. Detaches connections that fail mid-send.
        """
        connection_ids = list(self._by_user.get(user_id, set()))
        delivered = 0
        payload = message.model_dump()
        for cid in connection_ids:
            ws = self._sockets.get(cid)
            if ws is None:
                continue
            lock = self._locks.get(cid)
            try:
                if lock is not None:
                    async with lock:
                        await ws.send_json(payload)
                else:
                    await ws.send_json(payload)
                delivered += 1
            except Exception as exc:  # noqa: BLE001
                logger.warning(
                    "websocket_send_failed",
                    connection_id=str(cid),
                    user_id=str(user_id),
                    error=str(exc),
                )
                self.detach(connection_id=cid)
        return delivered


# Process-local singleton — imported by router and notification service.
manager = ConnectionManager()
