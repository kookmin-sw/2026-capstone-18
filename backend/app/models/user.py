"""User model — spec §6.3.

Anonymous-first identity: users are created via Supabase anonymous sign-in and
upgraded in-place when they sign in with Google. `supabase_user_id` is set for
both anonymous and registered users (Supabase native anon assigns a real Supabase
user_id). `anon_id` is set at creation if the user originated as anonymous and
remains in place after upgrade as a stable record of the anonymous period.
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, String, func
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user_settings import UserSettings


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        primary_key=True,
        default=uuid.uuid4,
    )
    supabase_user_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        unique=True,
        nullable=True,
        index=True,
    )
    anon_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        unique=True,
        nullable=True,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        server_default="user",
    )
    display_name: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
    )
    consent_raw_biosignals: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default="false",
    )
    consent_revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    settings: Mapped[UserSettings | None] = relationship(
        "UserSettings",
        back_populates="user",
        uselist=False,
        cascade="all, delete-orphan",
    )
