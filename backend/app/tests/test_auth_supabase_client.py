"""Tests for the Supabase HTTP client wrapper using respx mocks."""

from __future__ import annotations

import uuid
from typing import Any

import httpx
import pytest
import respx
from httpx import Response

from app.auth.supabase_client import (
    SupabaseAuthClient,
    SupabaseAuthError,
    SupabaseSession,
)
from app.tests.conftest_jwt import TEST_SUPABASE_URL


@pytest.fixture
def client(supabase_jwt_secret: str) -> SupabaseAuthClient:  # noqa: ARG001
    return SupabaseAuthClient(
        url=TEST_SUPABASE_URL,
        anon_key="test-anon-key",
        service_role_key="test-service-role-key",
    )


@pytest.mark.asyncio
async def test_sign_in_anonymously_returns_session(client: SupabaseAuthClient) -> None:
    user_id = str(uuid.uuid4())
    body = {
        "access_token": "at",
        "refresh_token": "rt",
        "expires_in": 3600,
        "token_type": "bearer",
        "user": {"id": user_id, "is_anonymous": True},
    }
    with respx.mock:
        respx.post(f"{TEST_SUPABASE_URL}/auth/v1/signup").mock(
            return_value=Response(200, json=body)
        )
        session = await client.sign_in_anonymously()
    assert isinstance(session, SupabaseSession)
    assert session.access_token == "at"
    assert session.refresh_token == "rt"
    assert session.user_id == uuid.UUID(user_id)
    assert session.is_anonymous is True


@pytest.mark.asyncio
async def test_sign_in_anonymously_raises_on_4xx(client: SupabaseAuthClient) -> None:
    with respx.mock:
        respx.post(f"{TEST_SUPABASE_URL}/auth/v1/signup").mock(
            return_value=Response(422, json={"msg": "anonymous sign-ins disabled"})
        )
        with pytest.raises(SupabaseAuthError):
            await client.sign_in_anonymously()


@pytest.mark.asyncio
async def test_sign_in_with_id_token_google(client: SupabaseAuthClient) -> None:
    user_id = str(uuid.uuid4())
    body = {
        "access_token": "at",
        "refresh_token": "rt",
        "expires_in": 3600,
        "token_type": "bearer",
        "user": {"id": user_id, "is_anonymous": False, "email": "u@example.com"},
    }
    with respx.mock:
        respx.post(f"{TEST_SUPABASE_URL}/auth/v1/token").mock(return_value=Response(200, json=body))
        session = await client.sign_in_with_id_token(provider="google", id_token="google-id-token")
    assert session.user_id == uuid.UUID(user_id)
    assert session.is_anonymous is False
    assert session.email == "u@example.com"


@pytest.mark.asyncio
async def test_admin_update_user_calls_admin_endpoint(client: SupabaseAuthClient) -> None:
    user_id = uuid.uuid4()
    captured: dict[str, Any] = {}

    def _capture(request: httpx.Request) -> Response:
        captured["headers"] = dict(request.headers)
        captured["body"] = request.read()
        return Response(200, json={"id": str(user_id)})

    with respx.mock:
        respx.patch(f"{TEST_SUPABASE_URL}/auth/v1/admin/users/{user_id}").mock(side_effect=_capture)
        await client.admin_update_user(
            user_id, email="u@example.com", user_metadata={"google_sub": "g-sub"}
        )

    assert "Bearer test-service-role-key" in captured["headers"]["authorization"]
    body = captured["body"]
    assert b"u@example.com" in body
    assert b"google_sub" in body


@pytest.mark.asyncio
async def test_refresh_session(client: SupabaseAuthClient) -> None:
    body = {
        "access_token": "new-at",
        "refresh_token": "new-rt",
        "expires_in": 3600,
        "token_type": "bearer",
        "user": {"id": str(uuid.uuid4()), "is_anonymous": False},
    }
    with respx.mock:
        respx.post(f"{TEST_SUPABASE_URL}/auth/v1/token").mock(return_value=Response(200, json=body))
        session = await client.refresh_session("old-rt")
    assert session.access_token == "new-at"


@pytest.mark.asyncio
async def test_sign_out(client: SupabaseAuthClient) -> None:
    with respx.mock:
        route = respx.post(f"{TEST_SUPABASE_URL}/auth/v1/logout").mock(return_value=Response(204))
        await client.sign_out("at")
    assert route.called
