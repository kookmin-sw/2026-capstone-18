"""Sanity check that every Sprint 4 endpoint is wired into the OpenAPI doc."""

from __future__ import annotations

import pytest
from httpx import AsyncClient

# (path, method) pairs we expect in the OpenAPI doc as of Sprint 5.
EXPECTED_ENDPOINTS = [
    ("/api/v1/auth/anon", "post"),
    ("/api/v1/auth/google", "post"),
    ("/api/v1/auth/refresh", "post"),
    ("/api/v1/auth/logout", "post"),
    ("/api/v1/me", "get"),
    ("/api/v1/account", "delete"),
    ("/api/v1/account/restore", "post"),
    ("/api/v1/events", "post"),
    ("/api/v1/events", "get"),
    ("/api/v1/events/{event_id}", "get"),
    ("/api/v1/events/{event_id}", "patch"),
    ("/api/v1/events/{event_id}", "delete"),
    ("/api/v1/cycles/period-start", "post"),
    ("/api/v1/cycles/current", "get"),
    ("/api/v1/cycles/history", "get"),
    ("/api/v1/cycles/{cycle_id}", "patch"),
    ("/api/v1/settings", "get"),
    ("/api/v1/settings", "patch"),
    ("/api/v1/consent", "get"),
    ("/api/v1/consent", "patch"),
    ("/api/v1/devices/fcm-token", "post"),
    ("/api/v1/sync/upload", "post"),
    ("/api/v1/sync/download", "get"),
    ("/api/v1/sync", "delete"),
    ("/api/v1/sync/biosignals", "post"),
]


@pytest.mark.asyncio
async def test_openapi_lists_every_sprint_4_endpoint(client: AsyncClient) -> None:
    resp = await client.get("/openapi.json")
    assert resp.status_code == 200
    spec = resp.json()
    for path, method in EXPECTED_ENDPOINTS:
        assert path in spec["paths"], f"{path} missing from OpenAPI doc"
        assert method in spec["paths"][path], f"{method.upper()} {path} missing"
        op = spec["paths"][path][method]
        assert op.get("summary"), f"{method.upper()} {path} has no summary"


@pytest.mark.asyncio
async def test_openapi_reports_app_version_0_7_0(client: AsyncClient) -> None:
    resp = await client.get("/openapi.json")
    assert resp.json()["info"]["version"] == "0.7.0"
