"""Tests for /me, account deletion, and account restoration."""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.main import app
from app.models.user import User


@pytest.mark.asyncio
async def test_me_returns_current_user(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(supabase_user_id=supabase_id, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.get(
                "/api/v1/me",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    body = response.json()
    assert body["supabase_user_id"] == str(supabase_id)
    assert body["role"] == "user"


@pytest.mark.asyncio
async def test_me_returns_401_without_token(
    db_session: AsyncSession,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as http:
        response = await http.get("/api/v1/me")
    assert response.status_code == 401


@pytest.mark.asyncio
async def test_delete_account_sets_deleted_at(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(supabase_user_id=supabase_id, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.delete(
                "/api/v1/account",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    refreshed = (await db_session.execute(select(User).where(User.id == user.id))).scalar_one()
    assert refreshed.deleted_at is not None


@pytest.mark.asyncio
async def test_restore_account_clears_deleted_at_within_grace(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(
        supabase_user_id=supabase_id,
        anon_id=uuid.uuid4(),
        deleted_at=datetime.now(tz=UTC) - timedelta(days=1),
    )
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post(
                "/api/v1/account/restore",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    refreshed = (await db_session.execute(select(User).where(User.id == user.id))).scalar_one()
    assert refreshed.deleted_at is None


@pytest.mark.asyncio
async def test_restore_account_rejects_after_grace_window(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(
        supabase_user_id=supabase_id,
        anon_id=uuid.uuid4(),
        deleted_at=datetime.now(tz=UTC) - timedelta(days=31),
    )
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post(
                "/api/v1/account/restore",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 410


@pytest.mark.asyncio
async def test_restore_account_returns_404_when_user_missing(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    # Mint a JWT for a Supabase user_id that has no User row.
    nonexistent_supabase_id = uuid.uuid4()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post(
                "/api/v1/account/restore",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(nonexistent_supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 404
    assert response.json()["reason"] == "user_not_found"


@pytest.mark.asyncio
async def test_restore_account_is_noop_when_not_deleted(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(supabase_user_id=supabase_id, anon_id=uuid.uuid4())
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post(
                "/api/v1/account/restore",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()

    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["deleted_at"] is None


@pytest.mark.asyncio
async def test_me_rejects_deleted_user_with_403(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    supabase_id = uuid.uuid4()
    user = User(
        supabase_user_id=supabase_id,
        anon_id=uuid.uuid4(),
        deleted_at=datetime.now(tz=UTC),
    )
    db_session.add(user)
    await db_session.flush()

    from app.db.dependencies import get_db

    async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
        yield db_session

    app.dependency_overrides[get_db] = _override_get_db
    try:
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.get(
                "/api/v1/me",
                headers={"Authorization": f"Bearer {make_jwt(sub=str(supabase_id))}"},
            )
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 403
