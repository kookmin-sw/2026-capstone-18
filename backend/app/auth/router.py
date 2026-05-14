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

import structlog
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.google import GoogleTokenError, verify_google_id_token
from app.auth.jwt import JWTVerificationError, verify_supabase_jwt
from app.auth.limiter import limiter
from app.auth.supabase_client import SupabaseAuthClient, SupabaseAuthError
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.auth import (
    EmailSignInRequest,
    EmailSignUpRequest,
    GoogleSignInRequest,
    LogoutResponse,
    PasswordForgotRequest,
    PasswordResetRequest,
    RefreshRequest,
    TokenResponse,
)
from app.services.user_settings import ensure_user_settings

logger = structlog.get_logger(__name__)
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
    db: AsyncSession,
    supabase_user_id: uuid.UUID,
    *,
    anon_id: uuid.UUID | None,
    display_name: str | None = None,
) -> User:
    """Return the User row for the given Supabase id, creating one if missing."""
    existing = (
        await db.execute(select(User).where(User.supabase_user_id == supabase_user_id))
    ).scalar_one_or_none()
    if existing is not None:
        if display_name and not existing.display_name:
            existing.display_name = display_name
            await db.flush()
        await ensure_user_settings(db, existing)
        return existing
    user = User(
        supabase_user_id=supabase_user_id,
        anon_id=anon_id,
        display_name=display_name,
    )
    db.add(user)
    await db.flush()
    await ensure_user_settings(db, user)
    return user


async def _abandon_anon_user(db: AsyncSession, supabase_user_id: uuid.UUID) -> None:
    """Soft-delete the anon User row whose upgrade was pre-empted by a collision."""
    row = (
        await db.execute(select(User).where(User.supabase_user_id == supabase_user_id))
    ).scalar_one_or_none()
    if row is not None and row.deleted_at is None:
        row.deleted_at = datetime.now(tz=UTC)
        await db.flush()


@router.post("/anon", response_model=TokenResponse, summary="Issue a JWT for an anonymous user")
@limiter.limit("10/minute")
async def sign_in_anonymously(
    request: Request,
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
        await ensure_user_settings(db, user)

    return TokenResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
        is_anonymous=session.is_anonymous,
    )


@router.post(
    "/google",
    response_model=TokenResponse,
    summary="Exchange a Google ID token for a Supabase session",
)
@limiter.limit("10/minute")
async def sign_in_with_google(
    request: Request,
    payload: GoogleSignInRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
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
                claims = await verify_supabase_jwt(token)
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


@router.post(
    "/email/login",
    response_model=TokenResponse,
    summary="Sign in with email and password",
)
@limiter.limit("10/minute")
async def sign_in_with_email_password(
    request: Request,
    payload: EmailSignInRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    client = _get_supabase_client()
    try:
        session = await client.sign_in_with_password(email=payload.email, password=payload.password)
    except SupabaseAuthError as exc:
        if 400 <= exc.status_code < 500:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"status": "error", "reason": "invalid_email_credentials"},
            ) from exc
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


@router.post(
    "/email/signup",
    response_model=TokenResponse,
    summary="Create a new email/password account",
)
@limiter.limit("5/minute")
async def sign_up_with_email_password(
    request: Request,
    payload: EmailSignUpRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    settings = get_settings()
    if not settings.email_signup_enabled:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "reason": "signup_disabled"},
        )

    client = _get_supabase_client()
    user_metadata = {"display_name": payload.display_name} if payload.display_name else None
    try:
        await client.sign_up_with_email(
            email=payload.email,
            password=payload.password,
            user_metadata=user_metadata,
            email_confirm=True,
        )
    except SupabaseAuthError as exc:
        body_str = str(exc.body).lower()
        if exc.status_code == 422 or "email_exists" in body_str or "already registered" in body_str:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail={"status": "error", "reason": "email_in_use"},
            ) from exc
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"status": "error", "reason": "supabase_unavailable"},
        ) from exc

    try:
        session = await client.sign_in_with_password(email=payload.email, password=payload.password)
    except SupabaseAuthError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail={"status": "error", "reason": "supabase_unavailable"},
        ) from exc

    await _ensure_user_row(db, session.user_id, anon_id=None, display_name=payload.display_name)
    return TokenResponse(
        access_token=session.access_token,
        refresh_token=session.refresh_token,
        expires_in=session.expires_in,
        is_anonymous=session.is_anonymous,
    )


@router.post("/refresh", response_model=TokenResponse, summary="Refresh an expired access token")
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


@router.post("/logout", response_model=LogoutResponse, summary="Revoke the caller's session")
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


@router.post(
    "/password/forgot",
    summary="Send a password-reset OTP by email (always returns 200)",
)
@limiter.limit("5/minute")
async def request_password_recovery(
    request: Request,
    payload: PasswordForgotRequest,
) -> dict[str, str]:
    """Always returns {status:"ok"} regardless of whether the email exists,
    so attackers cannot enumerate accounts via the recovery endpoint.
    Supabase 5xx responses log WARN for ops visibility (but the user still
    sees 200)."""
    client = _get_supabase_client()
    try:
        status_code = await client.request_password_recovery(email=payload.email)
    except Exception as exc:  # noqa: BLE001 — never propagate; user always sees 200
        logger.warning(
            "recovery_supabase_unavailable",
            email=payload.email,
            error=str(exc),
        )
        return {"status": "ok"}

    if 200 <= status_code < 300:
        logger.info("recovery_sent", email=payload.email)
    elif status_code == 404:
        logger.info("recovery_unknown_email", email=payload.email)
    elif status_code >= 500:
        logger.warning(
            "recovery_supabase_unavailable",
            email=payload.email,
            status_code=status_code,
        )
    else:
        logger.info(
            "recovery_unexpected_status",
            email=payload.email,
            status_code=status_code,
        )
    return {"status": "ok"}


@router.post(
    "/password/reset",
    response_model=TokenResponse,
    summary="Verify recovery OTP and set new password",
)
@limiter.limit("5/minute")
async def reset_password(
    request: Request,
    payload: PasswordResetRequest,
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TokenResponse:
    client = _get_supabase_client()
    try:
        session = await client.verify_recovery_otp_and_set_password(
            email=payload.email,
            otp=payload.otp,
            new_password=payload.new_password,
        )
    except SupabaseAuthError as exc:
        if exc.status_code in (400, 401, 403):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail={"status": "error", "reason": "invalid_otp"},
            ) from exc
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
