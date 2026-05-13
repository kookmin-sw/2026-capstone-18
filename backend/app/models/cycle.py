"""Cycle model — spec §6.3.

One row per logged period. The dominant access pattern is by user, not
by time range across users.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, Integer, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class Cycle(Base):
    __tablename__ = "cycles"
    __table_args__ = (Index("ix_cycles_user_period_start", "user_id", "period_start_date"),)

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
    period_start_date: Mapped[date] = mapped_column(Date, nullable=False)
    period_end_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    cycle_length_days: Mapped[int | None] = mapped_column(Integer, nullable=True)
    auto_detected: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    user_corrected: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="false")
    is_period_ongoing: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default="false",
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    user: Mapped[User] = relationship("User")
