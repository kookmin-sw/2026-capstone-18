"""UserSettings model — spec §6.3.

One-to-one with User. Created lazily the first time a user reads or writes settings.
Default values come straight from the spec.
"""

from __future__ import annotations

import uuid
from datetime import time
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Float, ForeignKey, Integer, String, Time
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class UserSettings(Base):
    __tablename__ = "user_settings"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        primary_key=True,
    )
    notification_max_per_day: Mapped[int] = mapped_column(
        Integer, nullable=False, server_default="5"
    )
    stress_threshold: Mapped[float] = mapped_column(Float, nullable=False, server_default="0.75")
    quiet_hours_start: Mapped[time] = mapped_column(Time, nullable=False, server_default="22:00")
    quiet_hours_end: Mapped[time] = mapped_column(Time, nullable=False, server_default="08:00")
    silence_during_meeting: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="true"
    )
    silence_during_exercise: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="true"
    )
    consent_audit_logging: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="true"
    )
    sleep_nudge_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, server_default="true"
    )
    language: Mapped[str] = mapped_column(String(8), nullable=False, server_default="ko")

    user: Mapped[User] = relationship("User", back_populates="settings")
