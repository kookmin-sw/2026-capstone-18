from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


def test_user_settings_model_has_field() -> None:
    from app.models.user_settings import UserSettings

    assert hasattr(UserSettings, "sleep_nudge_enabled")


@pytest.mark.asyncio
async def test_settings_endpoint_exposes_sleep_nudge_enabled(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    initial = await client.get("/api/v1/settings", headers=headers)
    assert initial.status_code == 200
    assert initial.json()["sleep_nudge_enabled"] is True

    patched = await client.patch(
        "/api/v1/settings",
        headers=headers,
        json={"sleep_nudge_enabled": False},
    )
    assert patched.status_code == 200
    assert patched.json()["sleep_nudge_enabled"] is False
