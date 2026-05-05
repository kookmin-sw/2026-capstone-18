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

    Auto-commits on a successful response, rolls back on any unhandled exception.
    Routes that perform writes only need to `db.add(...)` and `db.flush(...)`;
    the commit happens at request boundary. Read-only routes incur a no-op
    commit on a clean session, which is cheap.
    """
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        else:
            await session.commit()
