"""End-to-end tests for /api/v1/reports/drilldown."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_drilldown_smokes_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=luteal&frm=2026-09-01&to=2026-09-30",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["summary"]["event_count"] == 0
    assert body["summary"]["category_name"] == "Uncategorized"
    assert len(body["heatmap"]) == 12  # luteal default 17..28 inclusive
    assert body["recent_events"] == []


@pytest.mark.asyncio
async def test_drilldown_rejects_unknown_phase(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=weekend",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_drilldown_default_window_when_omitted(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=menstrual",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    # menstrual is days 1-5
    body = resp.json()
    assert {d["day"] for d in body["heatmap"]} == {1, 2, 3, 4, 5}


@pytest.mark.asyncio
async def test_drilldown_rejects_inverted_range(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=luteal&frm=2026-09-30&to=2026-09-01",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_drilldown_other_user_category_is_ignored(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    cat = (
        await client.post(
            "/api/v1/categories",
            headers=auth_headers(str(other.supabase_user_id)),
            json={"name": "Theirs", "color": "#111111"},
        )
    ).json()

    resp = await client.get(
        f"/api/v1/reports/drilldown?phase=luteal&category_id={cat['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    # Foreign category resolves to "Unknown" with 0 events.
    assert resp.status_code == 200
    assert resp.json()["summary"]["event_count"] == 0
