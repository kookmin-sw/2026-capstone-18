"""Supabase JWT verification.

Supabase issues asymmetric (ES256) JWTs signed with project keys exposed at
`<supabase_url>/auth/v1/.well-known/jwks.json`. We fetch and cache the JWKS,
match the token's `kid` header to a JWK, and verify signature + `iss`
(`<supabase_url>/auth/v1`) + `aud` (`authenticated`) + `exp`.

Sprint 3's original ADR-4 specified HS256 + project JWT secret. Supabase
projects have moved to asymmetric signing keys by default; the legacy HS256
secret is no longer what Supabase signs with. This module follows the same
JWKS pattern used by `app.auth.google` for Google ID tokens.
"""

from __future__ import annotations

from typing import Any

import httpx
from jose import JWTError
from jose import jwt as jose_jwt
from jose.exceptions import ExpiredSignatureError

from app.config import get_settings

_jwks_cache: dict[str, Any] | None = None
"""Module-level cache. Two concurrent cold-start requests can both fetch and
both write, but the writes are idempotent (same JWKS within a rotation window),
so we accept the rare double-fetch instead of paying for an asyncio.Lock."""


class JWTVerificationError(Exception):
    """Base class for JWT verification failures."""


class JWTExpiredError(JWTVerificationError):
    """Token's `exp` claim is in the past."""


class JWTInvalidError(JWTVerificationError):
    """Token signature, issuer, audience, or shape is invalid."""


async def _fetch_supabase_jwks(url: str) -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=5.0) as http:
        r = await http.get(url)
    r.raise_for_status()
    payload: dict[str, Any] = r.json()
    return payload


def _clear_jwks_cache() -> None:
    """Test hook — also useful if Supabase rotates keys mid-process."""
    global _jwks_cache
    _jwks_cache = None


async def _get_jwks(url: str) -> dict[str, Any]:
    global _jwks_cache
    if _jwks_cache is None:
        _jwks_cache = await _fetch_supabase_jwks(url)
    return _jwks_cache


async def verify_supabase_jwt(token: str) -> dict[str, Any]:
    """Verify a Supabase-issued JWT and return its claims.

    Raises:
        JWTExpiredError: if the token's `exp` is in the past.
        JWTInvalidError: for any other verification failure
            (bad signature, wrong issuer, wrong audience, missing kid, malformed token).
    """
    settings = get_settings()
    base = settings.supabase_url.rstrip("/")
    expected_issuer = f"{base}/auth/v1"
    jwks_url = f"{base}/auth/v1/.well-known/jwks.json"

    try:
        jwks = await _get_jwks(jwks_url)
    except httpx.HTTPError as exc:
        raise JWTInvalidError(f"could not fetch Supabase JWKS: {exc}") from exc

    try:
        unverified_header = jose_jwt.get_unverified_header(token)
    except JWTError as exc:
        raise JWTInvalidError(f"malformed token: {exc}") from exc
    kid = unverified_header.get("kid")
    key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        # Maybe Supabase rotated keys; refetch once.
        _clear_jwks_cache()
        try:
            jwks = await _get_jwks(jwks_url)
        except httpx.HTTPError as exc:
            raise JWTInvalidError(f"could not fetch Supabase JWKS: {exc}") from exc
        key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        raise JWTInvalidError(f"no matching JWK for kid={kid!r}")

    algorithms = [key.get("alg")] if key.get("alg") else ["ES256", "RS256"]
    try:
        claims: dict[str, Any] = jose_jwt.decode(
            token,
            key,
            algorithms=algorithms,
            audience="authenticated",
            issuer=expected_issuer,
        )
    except ExpiredSignatureError as exc:
        raise JWTExpiredError(str(exc)) from exc
    except JWTError as exc:
        raise JWTInvalidError(str(exc)) from exc
    return claims
