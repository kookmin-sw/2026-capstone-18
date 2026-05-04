"""Async SQLAlchemy engine + session factory.

One engine per process (recommended SQLAlchemy pattern). Sessions are short-lived
and tied to a single request via the `get_db` dependency in `app.db.dependencies`.
"""

from __future__ import annotations

from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from app.config import get_settings

_settings = get_settings()

engine: AsyncEngine = create_async_engine(
    _settings.database_url,
    echo=False,  # Set to True for SQL trace logs in local debugging
    pool_pre_ping=True,  # Detect broken connections before handing them out
    pool_size=5,
    max_overflow=10,
)

AsyncSessionLocal: async_sessionmaker[AsyncSession] = async_sessionmaker(
    bind=engine,
    expire_on_commit=False,
    autoflush=False,
)
