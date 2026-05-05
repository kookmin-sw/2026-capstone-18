"""Test fixtures for minting Supabase-shaped JWTs.

Supabase issues asymmetric (ES256) JWTs verified against the project's JWKS
endpoint. In tests we generate a fresh ES256 keypair at module load, expose
the public key as a JWK so `app.auth.jwt._fetch_supabase_jwks` can be patched
to return it, and use the matching private key to sign test tokens.
"""

from __future__ import annotations

import base64
import time
import uuid
from collections.abc import Callable, Generator
from typing import Any

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec
from jose import jwt as jose_jwt

TEST_SUPABASE_URL = "https://test-project.supabase.co"
TEST_KID = "test-supabase-kid"


def _b64url_uint(value: int, *, length: int) -> str:
    raw = value.to_bytes(length, "big")
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


_KEY = ec.generate_private_key(ec.SECP256R1())
TEST_PRIVATE_PEM = _KEY.private_bytes(
    encoding=serialization.Encoding.PEM,
    format=serialization.PrivateFormat.PKCS8,
    encryption_algorithm=serialization.NoEncryption(),
).decode("ascii")
_PUBLIC_NUMBERS = _KEY.public_key().public_numbers()
TEST_PUBLIC_JWK = {
    "kty": "EC",
    "crv": "P-256",
    "alg": "ES256",
    "use": "sig",
    "kid": TEST_KID,
    "x": _b64url_uint(_PUBLIC_NUMBERS.x, length=32),
    "y": _b64url_uint(_PUBLIC_NUMBERS.y, length=32),
}
TEST_JWKS = {"keys": [TEST_PUBLIC_JWK]}


def make_supabase_jwt(
    *,
    sub: str | None = None,
    is_anonymous: bool = False,
    role: str = "authenticated",
    expires_in: int = 3600,
    issuer: str = f"{TEST_SUPABASE_URL}/auth/v1",
    audience: str = "authenticated",
    kid: str = TEST_KID,
    private_pem: str = TEST_PRIVATE_PEM,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    """Mint an ES256 JWT shaped like the ones Supabase issues."""
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
    token: str = jose_jwt.encode(claims, private_pem, algorithm="ES256", headers={"kid": kid})
    return token


@pytest.fixture
def supabase_jwt_secret(monkeypatch: pytest.MonkeyPatch) -> Generator[str, None, None]:
    """Set Supabase Settings env to test values and prime the verifier's JWKS cache.

    Name kept for backward compat with existing tests; the verifier no longer uses
    the HS256 secret, but Settings still requires it as a non-empty string.
    """
    monkeypatch.setenv("SUPABASE_URL", TEST_SUPABASE_URL)
    monkeypatch.setenv("SUPABASE_ANON_KEY", "test-anon-key")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "test-service-role-key")
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "unused-by-jwks-verifier")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "test-client.apps.googleusercontent.com")
    from app.config import get_settings

    get_settings.cache_clear()

    # Prime the JWKS cache with our test public key so the verifier doesn't try
    # to hit a real Supabase project.
    from app.auth import jwt as jwt_module

    jwt_module._jwks_cache = TEST_JWKS

    yield "unused-by-jwks-verifier"

    jwt_module._clear_jwks_cache()


@pytest.fixture
def make_jwt(supabase_jwt_secret: str) -> Callable[..., str]:  # noqa: ARG001
    """Convenience: return a callable that mints tokens with the test private key."""
    return make_supabase_jwt
