"""Tests for the async SQLAlchemy engine and session factory."""

from __future__ import annotations

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

from app.db.session import AsyncSessionLocal, engine


def test_engine_is_async() -> None:
    assert isinstance(engine, AsyncEngine)


@pytest.mark.asyncio
async def test_session_can_query_postgres() -> None:
    async with AsyncSessionLocal() as session:
        assert isinstance(session, AsyncSession)
        result = await session.execute(text("SELECT 1 AS one"))
        row = result.one()
        assert row.one == 1


@pytest.mark.asyncio
async def test_session_rolls_back_on_exception() -> None:
    """Sessions used as a context manager should roll back on error."""
    with pytest.raises(RuntimeError):
        async with AsyncSessionLocal() as session:
            await session.execute(text("SELECT 1"))
            raise RuntimeError("simulated failure")
    # If we got here, the context manager swallowed the error properly during cleanup
    # and rolled back. A subsequent session works:
    async with AsyncSessionLocal() as session:
        result = await session.execute(text("SELECT 2 AS two"))
        assert result.one().two == 2
