"""Tests for direct Google ID token verification."""

from __future__ import annotations

import base64
import time
from unittest.mock import AsyncMock, patch

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from jose import jwt as jose_jwt

from app.auth.google import GoogleTokenError, verify_google_id_token


def _b64url_uint(value: int) -> str:
    raw = value.to_bytes((value.bit_length() + 7) // 8, "big") or b"\x00"
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


_KEY = rsa.generate_private_key(public_exponent=65537, key_size=2048)
TEST_PRIVATE_PEM = _KEY.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
).decode("ascii")
_PUBLIC_NUMBERS = _KEY.public_key().public_numbers()
TEST_PUBLIC_JWK = {
    "kty": "RSA",
    "alg": "RS256",
    "use": "sig",
    "kid": "test-kid",
    "n": _b64url_uint(_PUBLIC_NUMBERS.n),
    "e": _b64url_uint(_PUBLIC_NUMBERS.e),
}


def _make_google_jwt(
    *,
    sub: str = "google-sub-1",
    email: str = "u@example.com",
    aud: str = "test-client.apps.googleusercontent.com",
    iss: str = "https://accounts.google.com",
    expires_in: int = 3600,
) -> str:
    now = int(time.time())
    token: str = jose_jwt.encode(
        {
            "iss": iss,
            "aud": aud,
            "sub": sub,
            "email": email,
            "email_verified": True,
            "iat": now,
            "exp": now + expires_in,
        },
        TEST_PRIVATE_PEM,
        algorithm="RS256",
        headers={"kid": "test-kid"},
    )
    return token


@pytest.mark.asyncio
async def test_valid_google_token_returns_claims(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    token = _make_google_jwt()
    with patch(
        "app.auth.google._fetch_google_jwks",
        new=AsyncMock(return_value={"keys": [TEST_PUBLIC_JWK]}),
    ):
        from app.auth.google import _clear_jwks_cache

        _clear_jwks_cache()
        claims = await verify_google_id_token(token)
    assert claims["sub"] == "google-sub-1"
    assert claims["email"] == "u@example.com"


@pytest.mark.asyncio
async def test_google_token_wrong_audience_rejected(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    token = _make_google_jwt(aud="someone-else.apps.googleusercontent.com")
    with patch(
        "app.auth.google._fetch_google_jwks",
        new=AsyncMock(return_value={"keys": [TEST_PUBLIC_JWK]}),
    ):
        from app.auth.google import _clear_jwks_cache

        _clear_jwks_cache()
        with pytest.raises(GoogleTokenError):
            await verify_google_id_token(token)


@pytest.mark.asyncio
async def test_google_token_wrong_issuer_rejected(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    token = _make_google_jwt(iss="https://evil.example.com")
    with patch(
        "app.auth.google._fetch_google_jwks",
        new=AsyncMock(return_value={"keys": [TEST_PUBLIC_JWK]}),
    ):
        from app.auth.google import _clear_jwks_cache

        _clear_jwks_cache()
        with pytest.raises(GoogleTokenError):
            await verify_google_id_token(token)


@pytest.mark.asyncio
async def test_expired_google_token_rejected(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    token = _make_google_jwt(expires_in=-10)
    with patch(
        "app.auth.google._fetch_google_jwks",
        new=AsyncMock(return_value={"keys": [TEST_PUBLIC_JWK]}),
    ):
        from app.auth.google import _clear_jwks_cache

        _clear_jwks_cache()
        with pytest.raises(GoogleTokenError):
            await verify_google_id_token(token)
