"""SleepLog — one user-reported sleep window per night."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import (
    CheckConstraint,
    Computed,
    Date,
    DateTime,
    ForeignKey,
    Integer,
    String,
    Text,
    text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class SleepLog(Base):
    __tablename__ = "sleep_logs"
    __table_args__ = (
        CheckConstraint(
            "rating IN ('very_poor', 'poor', 'okay', 'good', 'great')",
            name="ck_sleep_logs_rating",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    fell_asleep_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    woke_up_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_on: Mapped[date] = mapped_column(Date, nullable=False)
    total_minutes: Mapped[int] = mapped_column(
        Integer,
        Computed(
            "(EXTRACT(EPOCH FROM (woke_up_at - fell_asleep_at)) / 60)::int",
            persisted=True,
        ),
        nullable=False,
    )
    rating: Mapped[str] = mapped_column(String(16), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )

    user: Mapped[User] = relationship("User")
