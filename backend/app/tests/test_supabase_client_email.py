"""Tests for SupabaseAuthClient email/password methods using httpx MockTransport."""

from __future__ import annotations

import json
import uuid
from typing import Any

import httpx
import pytest

from app.auth.supabase_client import SupabaseAuthClient, SupabaseAuthError


def _make_client(*, anon_key: str = "ak", service_role_key: str = "sk") -> SupabaseAuthClient:
    return SupabaseAuthClient(
        url="https://example.supabase.co",
        anon_key=anon_key,
        service_role_key=service_role_key,
    )


def _install_transport(monkeypatch: pytest.MonkeyPatch, handler: Any) -> None:
    transport = httpx.MockTransport(handler)
    orig = httpx.AsyncClient

    def _factory(*a: Any, **kw: Any) -> httpx.AsyncClient:
        return orig(*a, transport=transport, **kw)

    monkeypatch.setattr(httpx, "AsyncClient", _factory)


@pytest.mark.asyncio
async def test_sign_in_with_password_success(monkeypatch: pytest.MonkeyPatch) -> None:
    user_id = str(uuid.uuid4())
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["body"] = json.loads(request.content.decode())
        return httpx.Response(
            200,
            json={
                "access_token": "at",
                "refresh_token": "rt",
                "expires_in": 3600,
                "token_type": "bearer",
                "user": {
                    "id": user_id,
                    "is_anonymous": False,
                    "email": "u@example.com",
                },
            },
        )

    _install_transport(monkeypatch, handler)
    client = _make_client()
    session = await client.sign_in_with_password(email="u@example.com", password="pw")

    assert session.access_token == "at"
    assert session.refresh_token == "rt"
    assert session.expires_in == 3600
    assert session.user_id == uuid.UUID(user_id)
    assert session.is_anonymous is False
    assert session.email == "u@example.com"
    assert "grant_type=password" in captured["url"]
    assert captured["body"] == {"email": "u@example.com", "password": "pw"}


@pytest.mark.asyncio
async def test_sign_in_with_password_bad_creds_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(400, json={"error": "invalid_grant"})

    _install_transport(monkeypatch, handler)
    client = _make_client()
    with pytest.raises(SupabaseAuthError) as ei:
        await client.sign_in_with_password(email="u@example.com", password="bad")

    assert ei.value.status_code == 400


@pytest.mark.asyncio
async def test_sign_up_with_email_creates_admin_user(monkeypatch: pytest.MonkeyPatch) -> None:
    user_id = str(uuid.uuid4())
    captured: dict[str, Any] = {}

    def handler(request: httpx.Request) -> httpx.Response:
        captured["url"] = str(request.url)
        captured["headers"] = dict(request.headers)
        captured["body"] = json.loads(request.content.decode())
        return httpx.Response(200, json={"id": user_id, "email": "u@example.com"})

    _install_transport(monkeypatch, handler)
    client = _make_client(service_role_key="sk")
    result = await client.sign_up_with_email(email="u@example.com", password="pw")

    assert "/admin/users" in captured["url"]
    assert captured["headers"].get("authorization") == "Bearer sk"
    assert captured["body"]["email"] == "u@example.com"
    assert captured["body"]["password"] == "pw"
    assert captured["body"]["email_confirm"] is True
    assert result["id"] == user_id


@pytest.mark.asyncio
async def test_sign_up_with_email_duplicate_raises(monkeypatch: pytest.MonkeyPatch) -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(422, json={"code": "email_exists", "msg": "email_exists"})

    _install_transport(monkeypatch, handler)
    client = _make_client()
    with pytest.raises(SupabaseAuthError) as ei:
        await client.sign_up_with_email(email="u@example.com", password="pw")

    assert ei.value.status_code == 422
