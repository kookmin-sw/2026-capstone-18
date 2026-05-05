"""Auth router — Supabase-backed identity flows.

Endpoints:
- POST /api/v1/auth/anon — create an anonymous user via Supabase, mirror as a User row, return tokens.
- POST /api/v1/auth/google — id_token grant (or anon→Google upgrade); see Task 8.
- POST /api/v1/auth/refresh — refresh a session; see Task 9.
- POST /api/v1/auth/logout — revoke a session; see Task 9.
"""

from __future__ import annotations

import contextlib
import uuid
from datetime import UTC, datetime
from typing import Annotated, Any

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.google import GoogleTokenError, verify_google_id_token
from app.auth.jwt import JWTVerificationError, verify_supabase_jwt
from app.auth.supabase_client import SupabaseAuthClient, SupabaseAuthError
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.auth import (
    GoogleSignInRequest,
    LogoutResponse,
    RefreshRequest,
    TokenResponse,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _get_supabase_client() -> SupabaseAuthClient:
    """Indirection so tests can monkeypatch a single function."""
    s = get_settings()
    return SupabaseAuthClient(
        url=s.supabase_url,
        anon_key=s.supabase_anon_key,
        service_role_key=s.supabase_service_role_key,
    )


async def _verify_google_id_token(id_token: str) -> dict[str, Any]:
    """Indirection so tests can monkeypatch a single function."""
    return await verify_google_id_token(id_token)


async def _ensure_user_row(
    db: AsyncSession, supabase_user_id: uuid.UUID, *, anon_id: uuid.UUID | None
) -> User:
    """Return the User row for the given Supabase id, creating one if missing."""
    existing = (
        await db.execute(select(User).where(User.supabase_user_id == supabase_user_id))
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    user = User(supabase_user_id=supabase_user_id, anon_id=anon_id)
    db.add(user)
    await db.flush()
    return user


async def _abandon_anon_user(db: AsyncSession, supabase_user_id: uuid.UUID) -> None:
    """Soft-delete the anon User row whose upgrade was pre-empted by a collision."""
    row = (
        await db.execute(select(User).where(User.supabase_user_id == supabase_user_id))
    ).scalar_one_or_none()
    if row is not None and row.deleted_at is None:
        row.deleted_at = datetime.now(tz=UTC)
        await db.flush()


@router.post("/anon", response_model=TokenResponse)
async def sign_in_anonymously(
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    client = _get_supabase_client()
    try:
        session = await client.sign_in_anonymously()
    except SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"status": "error", "reason": "supabase_unavailable"},
        ) from exc

    existing = (
        await db.execute(select(User).where(User.supabase_user_id == session.user_id))
    ).scalar_one_or_none()
    if existing is None:
        user = User(
            supabase_user_id=session.user_id,
            anon_id=uuid.uuid4(),
        )
        db.add(user)
        await db.flush()

    return TokenResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
        is_anonymous=session.is_anonymous,
    )


@router.post("/google", response_model=TokenResponse)
async def sign_in_with_google(
    payload: GoogleSignInRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
    request: Request,
) -> TokenResponse:
    try:
        google_claims = await _verify_google_id_token(payload.id_token)
    except GoogleTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "invalid_google_token"},
        ) from exc

    google_email = google_claims.get("email")
    google_sub = google_claims["sub"]

    # Detect anon-upgrade case from the Authorization header.
    anon_supabase_id: uuid.UUID | None = None
    auth_header = request.headers.get("authorization")
    if auth_header:
        scheme, _, token = auth_header.partition(" ")
        if scheme.lower() == "bearer" and token:
            try:
                claims = verify_supabase_jwt(token)
            except JWTVerificationError:
                claims = None
            if claims and claims.get("is_anonymous") is True:
                try:
                    anon_supabase_id = uuid.UUID(claims["sub"])
                except (KeyError, ValueError):
                    anon_supabase_id = None

    client = _get_supabase_client()

    # Upgrade path.
    if anon_supabase_id is not None:
        upgraded = False
        try:
            await client.admin_update_user(
                anon_supabase_id,
                email=google_email,
                user_metadata={"google_sub": google_sub},
                email_confirm=True,
            )
            upgraded = True
        except SupabaseAuthError:
            # Collision: a Google user with this email/sub already exists in Supabase.
            # Soft-delete the abandoned anon row and fall through to plain Google sign-in
            # so the caller is logged into the existing Supabase account.
            await _abandon_anon_user(db, anon_supabase_id)

        if upgraded:
            # admin_update_user succeeded — issue tokens for the upgraded user.
            # If sign_in_with_id_token fails here it is a real downstream error and
            # MUST surface as 502, not as a collision fall-through (the user's anon
            # row is now mid-upgrade in Supabase and silently abandoning it would
            # leave a half-upgraded Supabase artifact).
            try:
                session = await client.sign_in_with_id_token(
                    provider="google", id_token=payload.id_token
                )
            except SupabaseAuthError as exc:
                raise HTTPException(
                    status_code=status.HTTP_502_BAD_GATEWAY,
                    detail={"status": "error", "reason": "supabase_unavailable"},
                ) from exc
            await _ensure_user_row(db, session.user_id, anon_id=None)
            return TokenResponse(
                access_token=session.access_token,
                refresh_token=session.refresh_token,
                expires_in=session.expires_in,
                is_anonymous=session.is_anonymous,
            )

    # Plain (or post-collision) Google sign-in.
    try:
        session = await client.sign_in_with_id_token(provider="google", id_token=payload.id_token)
    except SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"status": "error", "reason": "supabase_unavailable"},
        ) from exc

    await _ensure_user_row(db, session.user_id, anon_id=None)
    return TokenResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
        is_anonymous=session.is_anonymous,
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh_session(payload: RefreshRequest) -> TokenResponse:
    client = _get_supabase_client()
    try:
        session = await client.refresh_session(payload.refresh_token)
    except SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "refresh_failed"},
        ) from exc
    return TokenResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
        is_anonymous=session.is_anonymous,
    )


@router.post("/logout", response_model=LogoutResponse)
async def sign_out(request: Request) -> LogoutResponse:
    auth_header = request.headers.get("authorization") or ""
    scheme, _, token = auth_header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "missing_authorization_header"},
        )
    client = _get_supabase_client()
    # Best-effort: if Supabase rejects the token (already expired etc.)
    # the client is still effectively logged out locally.
    with contextlib.suppress(SupabaseAuthError):
        await client.sign_out(token)
    return LogoutResponse(status="ok")
