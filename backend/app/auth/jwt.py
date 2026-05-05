"""Supabase JWT verification.

Supabase issues HS256 JWTs signed with the project's JWT secret. We verify the
signature, the `iss` claim (must be `<supabase_url>/auth/v1`), the `aud` claim
(must be `authenticated`), and that the token has not expired.
"""

from __future__ import annotations

from typing import Any

from jose import JWTError
from jose import jwt as jose_jwt
from jose.exceptions import ExpiredSignatureError

from app.config import get_settings


class JWTVerificationError(Exception):
    """Base class for JWT verification failures."""


class JWTExpiredError(JWTVerificationError):
    """Token's `exp` claim is in the past."""


class JWTInvalidError(JWTVerificationError):
    """Token signature, issuer, audience, or shape is invalid."""


def verify_supabase_jwt(token: str) -> dict[str, Any]:
    """Verify a Supabase-issued HS256 JWT and return its claims.

    Raises:
        JWTExpiredError: if the token's `exp` is in the past.
        JWTInvalidError: for any other verification failure
            (bad signature, wrong issuer, wrong audience, malformed token).
    """
    settings = get_settings()
    expected_issuer = f"{settings.supabase_url.rstrip('/')}/auth/v1"
    try:
        claims: dict[str, Any] = jose_jwt.decode(
            token,
            settings.supabase_jwt_secret,
            algorithms=["HS256"],
            audience="authenticated",
            issuer=expected_issuer,
        )
    except ExpiredSignatureError as exc:
        raise JWTExpiredError(str(exc)) from exc
    except JWTError as exc:
        raise JWTInvalidError(str(exc)) from exc
    return claims
