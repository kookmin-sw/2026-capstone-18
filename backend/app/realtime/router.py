"""WebSocket /ws/realtime endpoint.

Auth: JWT delivered as the first message payload (type="auth"), not in the
query string, to avoid token leakage in access logs and traces.
Lifecycle: accept -> wait for auth message (5 s timeout) -> resolve User ->
register in DB + manager -> loop on receive_json -> on each client `ping`,
touch heartbeat in DB and reply with `system.heartbeat`. On disconnect,
unregister from DB + manager.
"""

from __future__ import annotations

import asyncio
import uuid
from typing import Annotated

import structlog
from fastapi import APIRouter, Depends, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import JWTVerificationError, verify_supabase_jwt
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.user import User
from app.realtime.manager import manager
from app.realtime.registry import register, touch_heartbeat, unregister
from app.schemas.realtime import OutboundMessage

router = APIRouter(tags=["realtime"])
logger = structlog.get_logger(__name__)


async def _resolve_user(token: str, db: AsyncSession) -> User | None:
    try:
        claims = await verify_supabase_jwt(token)
    except JWTVerificationError:
        return None
    sub = claims.get("sub")
    if not sub:
        return None
    try:
        sub_uuid = uuid.UUID(sub)
    except ValueError:
        return None
    row = (
        await db.execute(select(User).where(User.supabase_user_id == sub_uuid))
    ).scalar_one_or_none()
    if row is None or row.deleted_at is not None:
        return None
    return row


@router.websocket("/ws/realtime")
async def ws_realtime(
    websocket: WebSocket,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> None:
    await websocket.accept()

    try:
        auth_msg = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
    except (TimeoutError, Exception):
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    token = (
        auth_msg.get("token")
        if isinstance(auth_msg, dict) and auth_msg.get("type") == "auth"
        else None
    )
    if not token:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    user = await _resolve_user(token, db)
    if user is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    settings = get_settings()
    connection_id: uuid.UUID | None = None
    try:
        connection_id = await register(db, user_id=user.id, task_id=settings.task_id)
        manager.attach(connection_id=connection_id, user_id=user.id, websocket=websocket)
        logger.info(
            "websocket_connected",
            connection_id=str(connection_id),
            user_id=str(user.id),
            task_id=settings.task_id,
        )

        await websocket.send_json(OutboundMessage(type="system.heartbeat").model_dump())

        while True:
            msg = await websocket.receive_json()
            if isinstance(msg, dict) and msg.get("type") == "ping":
                await touch_heartbeat(db, connection_id=connection_id)
                await websocket.send_json(OutboundMessage(type="system.heartbeat").model_dump())
    except WebSocketDisconnect:
        pass
    except Exception as exc:  # noqa: BLE001
        logger.warning(
            "websocket_loop_error",
            connection_id=str(connection_id) if connection_id else None,
            error=str(exc),
            exc_type=type(exc).__name__,
        )
    finally:
        if connection_id is not None:
            manager.detach(connection_id=connection_id)
            await unregister(db, connection_id=connection_id)
            logger.info("websocket_disconnected", connection_id=str(connection_id))
