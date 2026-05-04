"""FastAPI dependencies for database access."""

from __future__ import annotations

from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import AsyncSessionLocal


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    """Yield a fresh AsyncSession for the duration of one request.

    Usage:
        @app.get("/items")
        async def list_items(db: AsyncSession = Depends(get_db)) -> list[Item]:
            ...

    Sessions are NOT auto-committed. Routes commit explicitly when they
    intend to persist changes.
    """
    async with AsyncSessionLocal() as session:
        yield session
