"""PATCH /api/v1/me."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_patch_me_sets_display_name(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    resp = await client.patch(
        "/api/v1/me",
        headers=headers,
        json={"display_name": "Amy"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["display_name"] == "Amy"

    # /me reflects the change.
    refreshed = await client.get("/api/v1/me", headers=headers)
    assert refreshed.json()["display_name"] == "Amy"


@pytest.mark.asyncio
async def test_patch_me_strips_whitespace(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "  Amy  "},
    )
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "Amy"


@pytest.mark.asyncio
async def test_patch_me_rejects_blank(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "   "},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_me_rejects_empty_body(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_me_caps_at_64_chars(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "A" * 65},
    )
    assert resp.status_code == 422
