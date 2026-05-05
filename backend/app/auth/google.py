"""Direct verification of Google-issued OIDC ID tokens.

Used by the anon→Google upgrade flow to extract the Google `sub` and email
before calling Supabase, so we can decide between log-into-existing and
upgrade-this-anon paths.
"""

from __future__ import annotations

from typing import Any

import httpx
from jose import JWTError
from jose import jwt as jose_jwt

from app.config import get_settings

GOOGLE_ISSUERS = {"https://accounts.google.com", "accounts.google.com"}
GOOGLE_JWKS_URL = "https://www.googleapis.com/oauth2/v3/certs"

_jwks_cache: dict[str, Any] | None = None


class GoogleTokenError(Exception):
    """Google ID token failed verification."""


async def _fetch_google_jwks() -> dict[str, Any]:
    async with httpx.AsyncClient(timeout=5.0) as http:
        r = await http.get(GOOGLE_JWKS_URL)
    r.raise_for_status()
    payload: dict[str, Any] = r.json()
    return payload


def _clear_jwks_cache() -> None:
    """Test hook — also useful if Google rotates keys mid-process."""
    global _jwks_cache
    _jwks_cache = None


async def _get_jwks() -> dict[str, Any]:
    global _jwks_cache
    if _jwks_cache is None:
        _jwks_cache = await _fetch_google_jwks()
    return _jwks_cache


async def verify_google_id_token(id_token: str) -> dict[str, Any]:
    """Verify a Google-issued OIDC ID token and return its claims.

    Raises:
        GoogleTokenError: for any failure (bad signature, wrong aud, wrong iss,
            expired, malformed).
    """
    settings = get_settings()
    try:
        jwks = await _get_jwks()
    except httpx.HTTPError as exc:
        raise GoogleTokenError(f"could not fetch Google JWKS: {exc}") from exc

    try:
        unverified_header = jose_jwt.get_unverified_header(id_token)
    except JWTError as exc:
        raise GoogleTokenError(f"malformed token: {exc}") from exc
    kid = unverified_header.get("kid")
    key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        # Maybe Google rotated keys; refetch once.
        _clear_jwks_cache()
        jwks = await _get_jwks()
        key = next((k for k in jwks.get("keys", []) if k.get("kid") == kid), None)
    if key is None:
        raise GoogleTokenError(f"no matching JWK for kid={kid!r}")

    try:
        claims: dict[str, Any] = jose_jwt.decode(
            id_token,
            key,
            algorithms=["RS256"],
            audience=settings.google_oauth_client_id,
        )
    except JWTError as exc:
        raise GoogleTokenError(str(exc)) from exc

    if claims.get("iss") not in GOOGLE_ISSUERS:
        raise GoogleTokenError(f"unexpected issuer: {claims.get('iss')!r}")
    return claims
