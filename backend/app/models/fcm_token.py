"""FcmToken model — one row per (user, device-token) pair.

The natural key is (user_id, token) — same user can have multiple devices.
Token uniqueness across users is guaranteed by Firebase itself; we do not
enforce it at the DB level (a unique constraint on `token` alone would
break the composite-PK pattern and add no value over what Firebase
already provides).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Index,
    PrimaryKeyConstraint,
    String,
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class FcmToken(Base):
    __tablename__ = "fcm_tokens"
    __table_args__ = (
        PrimaryKeyConstraint("user_id", "token", name="pk_fcm_tokens"),
        Index("ix_fcm_tokens_user_id", "user_id"),
        CheckConstraint(
            "platform IN ('android', 'ios')",
            name="ck_fcm_tokens_platform",
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    token: Mapped[str] = mapped_column(String(512), nullable=False)
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
    registered_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    last_seen_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )

    user: Mapped[User] = relationship("User")
