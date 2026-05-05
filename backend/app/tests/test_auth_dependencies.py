"""Tests for auth dependencies — get_current_user_id, get_current_user, require_admin."""

from __future__ import annotations

import uuid
from collections.abc import Callable

import pytest
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession
from starlette.requests import Request

from app.auth.dependencies import (
    get_current_user,
    get_current_user_id,
    require_admin,
)
from app.models.user import User


def _make_request(headers: dict[str, str]) -> Request:
    scope = {
        "type": "http",
        "headers": [(k.lower().encode(), v.encode()) for k, v in headers.items()],
    }
    return Request(scope)


@pytest.mark.asyncio
async def test_get_current_user_id_returns_uuid_from_valid_token(
    make_jwt: Callable[..., str],
) -> None:
    sub = str(uuid.uuid4())
    request = _make_request({"Authorization": f"Bearer {make_jwt(sub=sub)}"})
    result = await get_current_user_id(request)
    assert result == uuid.UUID(sub)


@pytest.mark.asyncio
async def test_get_current_user_id_raises_401_without_header(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    request = _make_request({})
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(request)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_id_raises_401_for_bad_scheme(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    request = _make_request({"Authorization": "Basic abc"})
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(request)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_id_raises_401_for_invalid_token(supabase_jwt_secret: str) -> None:  # noqa: ARG001
    request = _make_request({"Authorization": "Bearer not-a-jwt"})
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user_id(request)
    assert exc_info.value.status_code == 401


@pytest.mark.asyncio
async def test_get_current_user_returns_db_row(
    db_session: AsyncSession,
    make_jwt: Callable[..., str],  # noqa: ARG001
) -> None:
    supabase_id = uuid.uuid4()
    user = User(supabase_user_id=supabase_id, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    result = await get_current_user(supabase_id, db_session)
    assert result.id == user.id


@pytest.mark.asyncio
async def test_get_current_user_raises_404_when_no_row(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(uuid.uuid4(), db_session)
    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_get_current_user_raises_403_when_deleted(
    db_session: AsyncSession,
) -> None:
    from datetime import UTC, datetime

    supabase_id = uuid.uuid4()
    user = User(
        supabase_user_id=supabase_id,
        anon_id=uuid.uuid4(),
        deleted_at=datetime.now(tz=UTC),
    )
    db_session.add(user)
    await db_session.flush()

    with pytest.raises(HTTPException) as exc_info:
        await get_current_user(supabase_id, db_session)
    assert exc_info.value.status_code == 403


@pytest.mark.asyncio
async def test_require_admin_passes_for_admin_role(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4(), role="admin")
    db_session.add(user)
    await db_session.flush()

    result = await require_admin(user)
    assert result is user


@pytest.mark.asyncio
async def test_require_admin_raises_403_for_non_admin(db_session: AsyncSession) -> None:
    user = User(anon_id=uuid.uuid4(), role="user")
    db_session.add(user)
    await db_session.flush()

    with pytest.raises(HTTPException) as exc_info:
        await require_admin(user)
    assert exc_info.value.status_code == 403
