"""Global exception handler shape."""

from __future__ import annotations

from typing import Any

import pytest
import structlog
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_validation_error_returns_standard_envelope(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"model_confidence": 0.5},
    )
    assert resp.status_code == 422
    body = resp.json()
    assert body["status"] == "error"
    assert body["reason"] == "validation_error"
    assert isinstance(body["errors"], list)
    assert any(err["loc"][-1] == "detected_at" for err in body["errors"])


@pytest.mark.asyncio
async def test_validation_error_is_logged(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    from collections.abc import MutableMapping

    captured: list[dict[str, Any]] = []

    def _capture(
        _logger: Any, _method: str, event_dict: MutableMapping[str, Any]
    ) -> MutableMapping[str, Any]:
        captured.append(dict(event_dict))
        return event_dict

    structlog.reset_defaults()
    structlog.configure(
        processors=[_capture, structlog.processors.JSONRenderer()],
        cache_logger_on_first_use=False,
    )
    # Invalidate any cached bound loggers so the new processors take effect.
    from app.observability import exception_handlers as _eh

    _eh.logger = structlog.get_logger(_eh.__name__)
    try:
        await client.post(
            "/api/v1/events",
            headers=auth_headers(str(me.supabase_user_id)),
            json={"model_confidence": 0.5},
        )
    finally:
        from app.observability.logging import configure_logging

        configure_logging(level="INFO")
        _eh.logger = structlog.get_logger(_eh.__name__)

    assert any(ev.get("event") == "request_validation_failed" for ev in captured)


@pytest.mark.asyncio
async def test_http_exception_keeps_existing_detail(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        f"/api/v1/events/{'00000000-0000-0000-0000-000000000000'}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404
    body = resp.json()
    assert body["status"] == "error"
    assert body["reason"] == "event_not_found"


@pytest.mark.asyncio
async def test_unauthenticated_returns_standard_envelope(client: AsyncClient) -> None:
    resp = await client.get("/api/v1/me")
    assert resp.status_code == 401
    body = resp.json()
    assert body["status"] == "error"
    assert body["reason"] == "missing_authorization_header"


@pytest.mark.asyncio
async def test_unhandled_exception_returns_500_envelope(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """Override the auth dependency to raise an unhandled error and verify
    the global exception handler converts it to the standard 500 envelope.
    """
    from httpx import ASGITransport
    from httpx import AsyncClient as _AC

    from app.auth.dependencies import get_current_user
    from app.main import app

    me = await make_user()

    async def _boom() -> None:
        raise RuntimeError("boom")

    original = app.dependency_overrides.get(get_current_user)
    app.dependency_overrides[get_current_user] = _boom
    try:
        transport = ASGITransport(app=app, raise_app_exceptions=False)
        async with _AC(transport=transport, base_url="http://test") as ac:
            resp = await ac.post(
                "/api/v1/events",
                headers=auth_headers(str(me.supabase_user_id)),
                json={"detected_at": "2026-05-06T12:00:00+00:00"},
            )
    finally:
        if original is None:
            app.dependency_overrides.pop(get_current_user, None)
        else:
            app.dependency_overrides[get_current_user] = original

    assert resp.status_code == 500
    body = resp.json()
    assert body["status"] == "error"
    assert body["reason"] == "internal_server_error"
