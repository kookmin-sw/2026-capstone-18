"""Test fixtures for minting Supabase-shaped JWTs.

Backend verifies Supabase JWTs using HS256 + the project JWT secret. In tests we
override `Settings.supabase_jwt_secret` to a known value and mint tokens with
the same secret so the verifier accepts them.
"""

from __future__ import annotations

import time
import uuid
from collections.abc import Callable
from typing import Any

import pytest
from jose import jwt as jose_jwt

TEST_JWT_SECRET = "test-jwt-secret-do-not-use-in-prod"
TEST_SUPABASE_URL = "https://test-project.supabase.co"


def make_supabase_jwt(
    *,
    sub: str | None = None,
    is_anonymous: bool = False,
    role: str = "authenticated",
    expires_in: int = 3600,
    secret: str = TEST_JWT_SECRET,
    issuer: str = f"{TEST_SUPABASE_URL}/auth/v1",
    audience: str = "authenticated",
    extra_claims: dict[str, Any] | None = None,
) -> str:
    """Mint an HS256 JWT shaped like the ones Supabase issues."""
    now = int(time.time())
    claims: dict[str, Any] = {
        "iss": issuer,
        "aud": audience,
        "sub": sub or str(uuid.uuid4()),
        "iat": now,
        "exp": now + expires_in,
        "role": role,
        "is_anonymous": is_anonymous,
    }
    if extra_claims:
        claims.update(extra_claims)
    token: str = jose_jwt.encode(claims, secret, algorithm="HS256")
    return token


@pytest.fixture
def supabase_jwt_secret(monkeypatch: pytest.MonkeyPatch) -> str:
    """Override the JWT secret for the duration of a test."""
    monkeypatch.setenv("SUPABASE_JWT_SECRET", TEST_JWT_SECRET)
    monkeypatch.setenv("SUPABASE_URL", TEST_SUPABASE_URL)
    # Other Supabase fields too — Settings requires all of them.
    monkeypatch.setenv("SUPABASE_ANON_KEY", "test-anon-key")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client.apps.googleusercontent.com")
    # Bust the lru_cache so the override is picked up.
    from app.config import get_settings

    get_settings.cache_clear()
    return TEST_JWT_SECRET


@pytest.fixture
def make_jwt(supabase_jwt_secret: str) -> Callable[..., str]:  # noqa: ARG001
    """Convenience: return a callable that mints tokens with the test secret."""
    return make_supabase_jwt
