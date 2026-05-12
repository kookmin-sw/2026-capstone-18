"""StressEvent model — spec §6.3.

`stress_events` is a plain Postgres table; the composite primary key
`(id, detected_at)` is a holdover from a planned TimescaleDB hypertable
(AWS RDS dropped timescaledb support, so it stays a regular table).
The composite PK is harmless and kept to avoid a destructive migration.
Lookups by `id` alone use a separate non-unique index; routes always
also filter by `user_id` for ownership.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    PrimaryKeyConstraint,
    String,
    Text,
    func,
)
from sqlalchemy.dialects.postgresql import ARRAY, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class StressEvent(Base):
    __tablename__ = "stress_events"
    __table_args__ = (
        PrimaryKeyConstraint("id", "detected_at", name="pk_stress_events"),
        Index("ix_stress_events_id", "id"),
        Index("ix_stress_events_user_detected", "user_id", "detected_at"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        default=uuid.uuid4,
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    detected_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    model_confidence: Mapped[float | None] = mapped_column(Float, nullable=True)
    user_stress_level: Mapped[int | None] = mapped_column(Integer, nullable=True)
    mood_chips: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    category_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("trigger_categories.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
    )
    cycle_phase: Mapped[str | None] = mapped_column(String(16), nullable=True)
    cycle_day: Mapped[int | None] = mapped_column(Integer, nullable=True)
    logged: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    log_chips: Mapped[list[str] | None] = mapped_column(ARRAY(String), nullable=True)
    log_text: Mapped[str | None] = mapped_column(Text, nullable=True)
    notified: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    user: Mapped[User] = relationship("User")
