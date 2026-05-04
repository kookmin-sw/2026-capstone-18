"""SQLAlchemy declarative base.

All models in `app/models/` inherit from `Base` so Alembic's autogenerate
sees them via `Base.metadata`.
"""

from __future__ import annotations

from sqlalchemy.orm import DeclarativeBase


class Base(DeclarativeBase):
    """Shared declarative base for all ORM models."""
