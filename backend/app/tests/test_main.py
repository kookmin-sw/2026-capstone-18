"""Tests for the FastAPI app — /health, root redirect, OpenAPI metadata."""

from __future__ import annotations

from collections.abc import AsyncGenerator

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.dependencies import get_db
from app.main import app


@pytest.mark.asyncio
async def test_health_returns_ok() -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert "version" in body


@pytest.mark.asyncio
async def test_ready_returns_ok_when_db_responds(db_session: AsyncSession) -> None:
    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json() == {"status": "ok", "database": "ok"}


@pytest.mark.asyncio
async def test_ready_returns_503_when_db_fails() -> None:
    class BrokenSession:
        async def execute(self, *args: object, **kwargs: object) -> None:
            raise RuntimeError("database unavailable")

    async def _override_get_db() -> AsyncGenerator[BrokenSession, None]:
        yield BrokenSession()

    app.dependency_overrides[get_db] = _override_get_db
    transport = ASGITransport(app=app)
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            response = await client.get("/ready")
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 503
    assert response.json() == {"detail": {"status": "error", "database": "unreachable"}}


@pytest.mark.asyncio
async def test_root_redirects_to_docs() -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/", follow_redirects=False)

    assert response.status_code in (307, 308)
    assert response.headers["location"] == "/docs"


@pytest.mark.asyncio
async def test_openapi_metadata_present() -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/openapi.json")

    assert response.status_code == 200
    spec = response.json()
    assert spec["info"]["title"] == "little-signals backend"
    assert spec["info"]["version"]


@pytest.mark.asyncio
async def test_request_id_header_returned() -> None:
    """Each response carries an X-Request-ID header."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get("/health")

    request_id = response.headers.get("x-request-id")
    assert request_id is not None
    assert len(request_id) == 36  # uuid4 string length


@pytest.mark.asyncio
async def test_client_supplied_request_id_is_honored() -> None:
    """If the client sends X-Request-ID, the server echoes it back."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        response = await client.get(
            "/health",
            headers={"X-Request-ID": "my-correlation-id-1"},
        )

    assert response.headers["x-request-id"] == "my-correlation-id-1"
