"""End-to-end smoke for /api/v1/insights/*."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_calendar_endpoint_smokes_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/calendar?month=2026-05",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["month"] == "2026-05"
    assert len(body["days"]) == 31


@pytest.mark.asyncio
async def test_calendar_rejects_bad_month(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/calendar?month=2026-13",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_trends_default_window(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/trends",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    # Default 30-day window → 30 zero-stress points.
    assert len(resp.json()["points"]) == 30


@pytest.mark.asyncio
async def test_phase_averages_with_explicit_range(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/phase-averages?frm=2026-05-01&to=2026-05-31",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["phases"] == []  # no events for this user


@pytest.mark.asyncio
async def test_heatmap_returns_empty_for_new_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/heatmap?frm=2026-05-01&to=2026-05-31",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["rows"] == []


@pytest.mark.asyncio
async def test_patterns_returns_empty_for_new_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/patterns",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["patterns"] == []


@pytest.mark.asyncio
async def test_inverted_range_returns_422(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/trends?frm=2026-05-31&to=2026-05-01",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422
