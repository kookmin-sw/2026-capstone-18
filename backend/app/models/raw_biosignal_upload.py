"""RawBiosignalUpload model — opt-in raw biosignal blob references.

Hypertable on `recorded_at`. Composite PK `(id, recorded_at)` because
TimescaleDB hypertables require the partitioning column in every UNIQUE
index. Same pattern as `stress_events`.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
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


class RawBiosignalUpload(Base):
    __tablename__ = "raw_biosignal_uploads"
    __table_args__ = (
        PrimaryKeyConstraint("id", "recorded_at", name="pk_raw_biosignal_uploads"),
        Index("ix_raw_biosignal_uploads_id", "id"),
        Index(
            "ix_raw_biosignal_uploads_user_recorded",
            "user_id",
            "recorded_at",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), default=uuid.uuid4, nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    s3_object_key: Mapped[str] = mapped_column(String(512), nullable=False)
    signal_type: Mapped[str] = mapped_column(String(16), nullable=False)
    recorded_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    uploaded_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, server_default=func.now()
    )
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    user: Mapped[User] = relationship("User")
