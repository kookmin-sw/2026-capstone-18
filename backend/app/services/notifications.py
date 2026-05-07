"""NotificationService — chooses WebSocket or FCM based on connection state."""

from __future__ import annotations

import uuid
from dataclasses import dataclass

import structlog
from sqlalchemy.ext.asyncio import AsyncSession

from app.observability.metrics import notifications_sent_total
from app.observability.tracing import tracer
from app.realtime.manager import manager
from app.realtime.registry import list_for_user
from app.schemas.realtime import OutboundMessage
from app.services.fcm import send_to_user

logger = structlog.get_logger(__name__)


@dataclass
class NotifyResult:
    delivered_via_websocket: int = 0
    delivered_via_fcm: int = 0


class NotificationService:
    async def notify_user(
        self,
        db: AsyncSession,
        *,
        user_id: uuid.UUID,
        message: OutboundMessage,
    ) -> NotifyResult:
        result = NotifyResult()
        with tracer.start_as_current_span(
            "notify_user",
            attributes={"app.user_id": str(user_id), "app.message_type": message.type},
        ):
            try:
                result.delivered_via_websocket = await manager.broadcast_to_user(user_id, message)
                if result.delivered_via_websocket:
                    notifications_sent_total.labels(type="websocket").inc(
                        result.delivered_via_websocket
                    )
            except Exception as exc:  # noqa: BLE001
                logger.warning("notify_websocket_failed", user_id=str(user_id), error=str(exc))

            if result.delivered_via_websocket > 0:
                return result

            try:
                payload = {
                    "type": message.type,
                    "data": message.model_dump_json(),
                }
                result.delivered_via_fcm = await send_to_user(db, user_id=user_id, payload=payload)
                if result.delivered_via_fcm:
                    notifications_sent_total.labels(type="fcm").inc(result.delivered_via_fcm)
            except Exception as exc:  # noqa: BLE001
                logger.warning("notify_fcm_failed", user_id=str(user_id), error=str(exc))

            if result.delivered_via_websocket == 0 and result.delivered_via_fcm == 0:
                registered = await list_for_user(db, user_id=user_id)
                logger.info(
                    "notify_user_undeliverable",
                    user_id=str(user_id),
                    registered_websockets=len(list(registered)),
                )
            return result


notifier = NotificationService()
