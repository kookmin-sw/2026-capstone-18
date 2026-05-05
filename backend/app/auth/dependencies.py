"""FastAPI dependencies for authenticated routes.

Pattern for new endpoints:

    @router.get("/protected")
    async def endpoint(user: Annotated[User, Depends(get_current_user)]):
        ...

The chain is: Authorization header -> JWT verify -> Supabase user_id (UUID) ->
database User row.
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.jwt import (
    JWTExpiredError,
    JWTInvalidError,
    verify_supabase_jwt,
)
from app.db.dependencies import get_db
from app.models.user import User


async def get_current_user_id(request: Request) -> uuid.UUID:
    """Extract and verify the bearer JWT, return the Supabase user_id (sub claim)."""
    header = request.headers.get("authorization")
    if not header:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "missing_authorization_header"},
            headers={"WWW-Authenticate": "Bearer"},
        )
    scheme, _, token = header.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "invalid_authorization_scheme"},
            headers={"WWW-Authenticate": "Bearer"},
        )

    try:
        claims = await verify_supabase_jwt(token)
    except JWTExpiredError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "token_expired"},
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc
    except JWTInvalidError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "token_invalid"},
            headers={"WWW-Authenticate": "Bearer"},
        ) from exc

    sub = claims.get("sub")
    if not sub:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "missing_sub_claim"},
        )
    try:
        return uuid.UUID(sub)
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"status": "error", "reason": "non_uuid_sub_claim"},
        ) from exc


async def get_current_user(
    user_id: Annotated[uuid.UUID, Depends(get_current_user_id)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> User:
    """Look up the User row matching the Supabase user_id from the JWT.

    Raises:
        404 if no matching row exists. The auth endpoints are responsible for
            creating the row before returning a JWT to the client.
        403 if the row's `deleted_at` is set (account in 30-day grace).
    """
    row = (
        await db.execute(select(User).where(User.supabase_user_id == user_id))
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "user_not_found"},
        )
    if row.deleted_at is not None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "reason": "account_pending_deletion"},
        )
    return row


async def require_admin(
    user: Annotated[User, Depends(get_current_user)],
) -> User:
    """Reject if the current user is not an admin."""
    if user.role != "admin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={"status": "error", "reason": "admin_required"},
        )
    return user
