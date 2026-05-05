"""Shared pytest fixtures.

Test database: set DATABASE_URL to TEST_DATABASE_URL BEFORE importing app
modules so the production engine in app.db.session binds to the test DB.

Engine pool hygiene: the module-level async engine is tied to the asyncio
event loop that first borrowed a connection. pytest-asyncio creates a fresh
loop per test, so connections in the pool from a previous test are bound to
a closed loop. The next test that touches the pool hits "Event loop is
closed" during pool_pre_ping. The autouse engine-dispose fixture ensures
each test starts with an empty pool on its own loop.

Fixtures:
- `client`: httpx AsyncClient wired to the FastAPI app via ASGI transport
- `db_session`: AsyncSession against the test database, rolled back per test
- `test_engine`: session-scoped engine for the rollback fixture (separate
  from the production engine to avoid pool conflicts with other tests)
"""

from __future__ import annotations

import os
from collections.abc import AsyncGenerator, AsyncIterator

import pytest_asyncio
from httpx import ASGITransport, AsyncClient
from sqlalchemy import NullPool
from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

# Force tests onto the test DB BEFORE importing any app module that reads settings.
TEST_DATABASE_URL = os.environ.get(
    "TEST_DATABASE_URL",
    "postgresql+asyncpg://little_signals:dev_only_password@localhost:5432/little_signals_test",
)
os.environ["DATABASE_URL"] = TEST_DATABASE_URL

# Sprint 3 Supabase fields are required Settings — provide harmless test defaults
# so test collection works without a populated .env. Individual tests override
# these via monkeypatch + Settings.cache_clear() when they need real values.
os.environ.setdefault("SUPABASE_URL", "https://test-project.supabase.co")
os.environ.setdefault("SUPABASE_ANON_KEY", "test-anon-key")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")
os.environ.setdefault("SUPABASE_JWT_SECRET", "test-jwt-secret-do-not-use-in-prod")
os.environ.setdefault("GOOGLE_OAUTH_CLIENT_ID", "test-client.apps.googleusercontent.com")

# Imports below MUST come after the env override above
from app.db.dependencies import get_db  # noqa: E402
from app.db.session import engine  # noqa: E402
from app.main import app  # noqa: E402


@pytest_asyncio.fixture(autouse=True)
async def _dispose_engine_between_tests() -> AsyncIterator[None]:
    """Dispose the production engine after each test to free pooled connections.

    Required because pytest-asyncio rebuilds the event loop per test; pooled
    connections from a closed loop trigger errors on the next pool_pre_ping.
    """
    yield
    await engine.dispose()


@pytest_asyncio.fixture(scope="session")
async def test_engine() -> AsyncIterator:  # type: ignore[type-arg]
    """Session-scoped engine for the rollback-style db_session fixture.

    Separate from the production engine so disposing the production engine
    between tests doesn't disturb in-flight transactions on this one.
    """
    # NullPool: don't reuse connections across tests. pytest-asyncio creates a
    # fresh event loop per test, so any pooled connection from a prior test is
    # bound to a closed loop and explodes on the next pool_pre_ping.
    eng = create_async_engine(TEST_DATABASE_URL, poolclass=NullPool)
    yield eng
    await eng.dispose()


@pytest_asyncio.fixture
async def db_session(test_engine) -> AsyncGenerator[AsyncSession, None]:  # type: ignore[no-untyped-def]
    """Per-test transactional session — rolls back changes when the test ends."""
    connection = await test_engine.connect()
    transaction = await connection.begin()
    session_factory = async_sessionmaker(bind=connection, expire_on_commit=False)
    session = session_factory()
    try:
        yield session
    finally:
        await session.close()
        await transaction.rollback()
        await connection.close()


@pytest_asyncio.fixture
async def client(db_session: AsyncSession) -> AsyncGenerator[AsyncClient, None]:
    """httpx client that uses the per-test rolled-back DB session."""

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac
    app.dependency_overrides.clear()
