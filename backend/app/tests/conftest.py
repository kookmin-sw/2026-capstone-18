"""Shared pytest fixtures.

The async SQLAlchemy engine in ``app.db.session`` is module-level and tied to
the asyncio event loop that first borrowed a connection. ``pytest-asyncio`` in
function scope creates a fresh loop per test, so any pooled connection from a
previous test is bound to a closed loop. The next test that touches the pool
hits ``RuntimeError: Event loop is closed`` during ``pool_pre_ping``.

We dispose the engine after each test so each test starts with an empty pool
on its own loop.
"""

from __future__ import annotations

from collections.abc import AsyncIterator

import pytest_asyncio

from app.db.session import engine


@pytest_asyncio.fixture(autouse=True)
async def _dispose_engine_between_tests() -> AsyncIterator[None]:
    yield
    await engine.dispose()
