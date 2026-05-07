"""Sprint 8a — /metrics endpoint exposure + custom metric registration tests."""

from __future__ import annotations

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_metrics_endpoint_returns_prometheus_text(client: AsyncClient) -> None:
    resp = await client.get("/metrics")
    assert resp.status_code == 200
    assert resp.headers["content-type"].startswith("text/plain")
    body = resp.text
    # prometheus-fastapi-instrumentator default metric
    assert "http_request_duration_seconds" in body or "http_requests_total" in body


@pytest.mark.asyncio
async def test_metrics_endpoint_exposes_custom_counters(client: AsyncClient) -> None:
    resp = await client.get("/metrics")
    body = resp.text
    assert "events_created_total" in body
    assert "notifications_sent_total" in body
    assert "active_websocket_connections" in body
    assert "db_query_duration_seconds" in body


def test_custom_metrics_have_help_text() -> None:
    """Every Prometheus metric needs a HELP comment for ops sanity."""
    from app.observability.metrics import (
        active_websocket_connections,
        db_query_duration_seconds,
        events_created_total,
        notifications_sent_total,
    )

    for metric in (
        events_created_total,
        notifications_sent_total,
        active_websocket_connections,
        db_query_duration_seconds,
    ):
        assert metric._documentation, f"{metric._name} missing HELP text"
