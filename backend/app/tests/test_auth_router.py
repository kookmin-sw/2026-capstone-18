"""Tests for the auth router — anon sign-in only in this commit; google + refresh + logout follow."""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.supabase_client import SupabaseSession
from app.main import app
from app.models.user import User


def _supabase_session_for(user_id: uuid.UUID, *, anon: bool = True) -> SupabaseSession:
    return SupabaseSession(
        access_token="test-access-token",
        refresh_token="test-refresh-token",
        expires_in=3600,
        user_id=user_id,
        is_anonymous=anon,
    )


@pytest.mark.asyncio
async def test_post_auth_anon_creates_user_and_returns_tokens(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    supabase_id = uuid.uuid4()
    fake_session = _supabase_session_for(supabase_id, anon=True)

    with patch(
        "app.auth.router._get_supabase_client",
    ) as get_client:
        client_mock = AsyncMock()
        client_mock.sign_in_anonymously.return_value = fake_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post("/api/v1/auth/anon")
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    body: dict[str, Any] = response.json()
    assert body["access_token"] == "test-access-token"
    assert body["refresh_token"] == "test-refresh-token"
    assert body["expires_in"] == 3600
    assert body["token_type"] == "bearer"
    assert body["is_anonymous"] is True

    row = (
        await db_session.execute(select(User).where(User.supabase_user_id == supabase_id))
    ).scalar_one()
    assert row.anon_id is not None
    assert row.deleted_at is None
