"""JWT verification tests."""

from __future__ import annotations

import uuid
from collections.abc import Callable

import pytest

from app.auth.jwt import (
    JWTExpiredError,
    JWTInvalidError,
    JWTVerificationError,
    verify_supabase_jwt,
)
from app.tests.conftest_jwt import make_supabase_jwt


def test_valid_token_returns_claims(make_jwt: Callable[..., str]) -> None:
    sub = str(uuid.uuid4())
    token = make_jwt(sub=sub)
    claims = verify_supabase_jwt(token)
    assert claims["sub"] == sub
    assert claims["role"] == "authenticated"
    assert claims["is_anonymous"] is False


def test_anonymous_token_carries_is_anonymous_true(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(is_anonymous=True)
    claims = verify_supabase_jwt(token)
    assert claims["is_anonymous"] is True


def test_expired_token_raises_expired_error(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(expires_in=-10)  # already expired
    with pytest.raises(JWTExpiredError):
        verify_supabase_jwt(token)


def test_token_with_wrong_signature_raises_invalid_error(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    token = make_supabase_jwt(secret="not-the-real-secret")
    with pytest.raises(JWTInvalidError):
        verify_supabase_jwt(token)


def test_token_with_wrong_issuer_raises_invalid_error(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(issuer="https://evil.example.com/auth/v1")
    with pytest.raises(JWTInvalidError):
        verify_supabase_jwt(token)


def test_token_with_wrong_audience_raises_invalid_error(make_jwt: Callable[..., str]) -> None:
    token = make_jwt(audience="some-other-aud")
    with pytest.raises(JWTInvalidError):
        verify_supabase_jwt(token)


def test_malformed_token_raises_invalid_error(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    with pytest.raises(JWTInvalidError):
        verify_supabase_jwt("not-even-a-jwt")


def test_jwt_verification_error_is_base_for_specific_errors() -> None:
    assert issubclass(JWTExpiredError, JWTVerificationError)
    assert issubclass(JWTInvalidError, JWTVerificationError)
