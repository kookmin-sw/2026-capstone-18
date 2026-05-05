"""JWT verification tests."""

from __future__ import annotations

import uuid
from collections.abc import Callable

import pytest
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

from app.auth.jwt import (
    JWTExpiredError,
    JWTInvalidError,
    JWTVerificationError,
    verify_supabase_jwt,
)
from app.tests.conftest_jwt import TEST_KID, make_supabase_jwt


@pytest.mark.asyncio
async def test_valid_token_returns_claims(make_jwt: Callable[..., str]) -> None:
    sub = str(uuid.uuid4())
    token = make_jwt(sub=sub)
    claims = await verify_supabase_jwt(token)
    assert claims["sub"] == sub
    assert claims["role"] == "authenticated"
    assert claims["is_anonymous"] is False


@pytest.mark.asyncio
async def test_anonymous_token_carries_is_anonymous_true(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(is_anonymous=True)
    claims = await verify_supabase_jwt(token)
    assert claims["is_anonymous"] is True


@pytest.mark.asyncio
async def test_expired_token_raises_expired_error(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(expires_in=-10)  # already expired
    with pytest.raises(JWTExpiredError):
        await verify_supabase_jwt(token)


@pytest.mark.asyncio
async def test_token_signed_by_unrelated_key_raises_invalid_error(
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    rogue_key = ec.generate_private_key(ec.SECP256R1())
    rogue_pem = rogue_key.private_bytes(
        encoding=serialization.Encoding.PEM,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    ).decode("ascii")
    # Same kid as test JWKS — the verifier picks our public key, but the signature
    # is from a different private key, so verification must fail.
    token = make_supabase_jwt(private_pem=rogue_pem, kid=TEST_KID)
    with pytest.raises(JWTInvalidError):
        await verify_supabase_jwt(token)


@pytest.mark.asyncio
async def test_token_with_unknown_kid_raises_invalid_error(
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    # kid that won't match any JWK in the cached set.
    token = make_supabase_jwt(kid="not-our-kid")
    # The verifier refetches once on miss — patch _fetch_supabase_jwks so the
    # refetch doesn't try to hit the real Supabase project.
    from unittest.mock import AsyncMock, patch

    with (
        patch(
            "app.auth.jwt._fetch_supabase_jwks",
            new=AsyncMock(return_value={"keys": []}),
        ),
        pytest.raises(JWTInvalidError),
    ):
        await verify_supabase_jwt(token)


@pytest.mark.asyncio
async def test_token_with_wrong_issuer_raises_invalid_error(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(issuer="https://evil.example.com/auth/v1")
    with pytest.raises(JWTInvalidError):
        await verify_supabase_jwt(token)


@pytest.mark.asyncio
async def test_token_with_wrong_audience_raises_invalid_error(
    make_jwt: Callable[..., str],
) -> None:
    token = make_jwt(audience="some-other-aud")
    with pytest.raises(JWTInvalidError):
        await verify_supabase_jwt(token)


@pytest.mark.asyncio
async def test_malformed_token_raises_invalid_error(
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    with pytest.raises(JWTInvalidError):
        await verify_supabase_jwt("not-even-a-jwt")


def test_jwt_verification_error_is_base_for_specific_errors() -> None:
    assert issubclass(JWTExpiredError, JWTVerificationError)
    assert issubclass(JWTInvalidError, JWTVerificationError)
