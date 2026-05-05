"""Auth router — Supabase-backed identity flows.

Endpoints:
- POST /api/v1/auth/anon — create an anonymous user via Supabase, mirror as a User row, return tokens.
- POST /api/v1/auth/google — id_token grant (or anon→Google upgrade); see Task 8.
- POST /api/v1/auth/refresh — refresh a session; see Task 9.
- POST /api/v1/auth/logout — revoke a session; see Task 9.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.supabase_client import SupabaseAuthClient, SupabaseAuthError
from app.config import get_settings
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.auth import TokenResponse

router = APIRouter(prefix="/auth", tags=["auth"])


def _get_supabase_client() -> SupabaseAuthClient:
    """Indirection so tests can monkeypatch a single function."""
    s = get_settings()
    return SupabaseAuthClient(
        url=s.supabase_url,
        anon_key=s.supabase_anon_key,
        service_role_key=s.supabase_service_role_key,
    )


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
