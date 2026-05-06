"""WebsocketConnection model — Sprint 5 connection registry.

A small, frequently-mutated table. Each row represents one open WebSocket on
one ECS task. `task_id` lets a task identify rows it owns (for startup cleanup)
and lets the NotificationService decide whether a user is connected to *this*
task (deliver via WS) versus only some other task (deliver via FCM, since we
don't run cross-task pub/sub in v1).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class WebsocketConnection(Base):
    __tablename__ = "websocket_connections"
    __table_args__ = (
        Index("ix_websocket_connections_user_id", "user_id"),
        Index("ix_websocket_connections_task_id", "task_id"),
        Index("ix_websocket_connections_last_seen_at", "last_seen_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    task_id: Mapped[str] = mapped_column(String(128), nullable=False)
    connected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    user: Mapped[User] = relationship("User")
