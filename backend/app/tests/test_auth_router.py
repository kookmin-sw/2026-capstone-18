"""Tests for the auth router — anon sign-in only in this commit; google + refresh + logout follow."""

from __future__ import annotations

import uuid
from collections.abc import AsyncGenerator
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.supabase_client import SupabaseSession
from app.main import app
from app.models.user import User


def _supabase_session_for(user_id: uuid.UUID, *, anon: bool = True) -> SupabaseSession:
    return SupabaseSession(
        access_token="test-access-token",
        refresh_token="test-refresh-token",
        expires_in=3600,
        user_id=user_id,
        is_anonymous=anon,
    )


@pytest.mark.asyncio
async def test_post_auth_anon_creates_user_and_returns_tokens(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    supabase_id = uuid.uuid4()
    fake_session = _supabase_session_for(supabase_id, anon=True)

    with patch(
        "app.auth.router._get_supabase_client",
    ) as get_client:
        client_mock = AsyncMock()
        client_mock.sign_in_anonymously.return_value = fake_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post("/api/v1/auth/anon")
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    body: dict[str, Any] = response.json()
    assert body["access_token"] == "test-access-token"
    assert body["refresh_token"] == "test-refresh-token"
    assert body["expires_in"] == 3600
    assert body["token_type"] == "bearer"
    assert body["is_anonymous"] is True

    row = (
        await db_session.execute(select(User).where(User.supabase_user_id == supabase_id))
    ).scalar_one()
    assert row.anon_id is not None
    assert row.deleted_at is None


@pytest.fixture
def google_claims() -> dict[str, Any]:
    return {
        "sub": "google-sub-1",
        "email": "u@example.com",
        "email_verified": True,
        "iss": "https://accounts.google.com",
        "aud": "test-client.apps.googleusercontent.com",
    }


@pytest.mark.asyncio
async def test_google_signin_creates_new_user_when_no_anon(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    google_claims: dict[str, Any],
) -> None:
    new_supabase_id = uuid.uuid4()
    fake_session = _supabase_session_for(new_supabase_id, anon=False)

    with (
        patch(
            "app.auth.router._verify_google_id_token",
            new=AsyncMock(return_value=google_claims),
        ),
        patch("app.auth.router._get_supabase_client") as get_client,
    ):
        client_mock = AsyncMock()
        client_mock.sign_in_with_id_token.return_value = fake_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post("/api/v1/auth/google", json={"id_token": "google-token"})
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["is_anonymous"] is False
    row = (
        await db_session.execute(select(User).where(User.supabase_user_id == new_supabase_id))
    ).scalar_one()
    assert row.anon_id is None  # new user, never anon


@pytest.mark.asyncio
async def test_google_signin_returns_existing_user(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    google_claims: dict[str, Any],
) -> None:
    existing_supabase_id = uuid.uuid4()
    existing = User(supabase_user_id=existing_supabase_id, anon_id=uuid.uuid4())
    db_session.add(existing)
    await db_session.flush()

    fake_session = _supabase_session_for(existing_supabase_id, anon=False)
    with (
        patch(
            "app.auth.router._verify_google_id_token",
            new=AsyncMock(return_value=google_claims),
        ),
        patch("app.auth.router._get_supabase_client") as get_client,
    ):
        client_mock = AsyncMock()
        client_mock.sign_in_with_id_token.return_value = fake_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post("/api/v1/auth/google", json={"id_token": "google-token"})
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    rows = (await db_session.execute(select(User))).scalars().all()
    assert len([r for r in rows if r.supabase_user_id == existing_supabase_id]) == 1


@pytest.mark.asyncio
async def test_anon_to_google_upgrades_in_place(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    google_claims: dict[str, Any],
) -> None:
    anon_supabase_id = uuid.uuid4()
    anon = User(supabase_user_id=anon_supabase_id, anon_id=uuid.uuid4())
    db_session.add(anon)
    await db_session.flush()

    upgraded_session = _supabase_session_for(anon_supabase_id, anon=False)

    from app.tests.conftest_jwt import make_supabase_jwt

    anon_jwt = make_supabase_jwt(sub=str(anon_supabase_id), is_anonymous=True)

    with (
        patch(
            "app.auth.router._verify_google_id_token",
            new=AsyncMock(return_value=google_claims),
        ),
        patch("app.auth.router._get_supabase_client") as get_client,
    ):
        client_mock = AsyncMock()
        client_mock.admin_update_user.return_value = {"id": str(anon_supabase_id)}
        client_mock.sign_in_with_id_token.return_value = upgraded_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post(
                    "/api/v1/auth/google",
                    json={"id_token": "google-token"},
                    headers={"Authorization": f"Bearer {anon_jwt}"},
                )
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    assert response.json()["is_anonymous"] is False
    client_mock.admin_update_user.assert_awaited_once()
    # Original anon row is preserved (not deleted) — same supabase_user_id, anon_id intact.
    row = (
        await db_session.execute(select(User).where(User.supabase_user_id == anon_supabase_id))
    ).scalar_one()
    assert row.id == anon.id
    assert row.anon_id is not None
    assert row.deleted_at is None


@pytest.mark.asyncio
async def test_anon_to_google_collision_logs_in_existing_and_abandons_anon(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    google_claims: dict[str, Any],
) -> None:
    # Pre-existing Google user.
    existing_supabase_id = uuid.uuid4()
    existing = User(supabase_user_id=existing_supabase_id)
    db_session.add(existing)
    # Current anon user.
    anon_supabase_id = uuid.uuid4()
    anon = User(supabase_user_id=anon_supabase_id, anon_id=uuid.uuid4())
    db_session.add(anon)
    await db_session.flush()

    from app.auth.supabase_client import SupabaseAuthError

    existing_session = _supabase_session_for(existing_supabase_id, anon=False)

    from app.tests.conftest_jwt import make_supabase_jwt

    anon_jwt = make_supabase_jwt(sub=str(anon_supabase_id), is_anonymous=True)

    def _admin_update_raises(*args: Any, **kwargs: Any) -> Any:
        raise SupabaseAuthError(422, {"msg": "email exists"})

    with (
        patch(
            "app.auth.router._verify_google_id_token",
            new=AsyncMock(return_value=google_claims),
        ),
        patch("app.auth.router._get_supabase_client") as get_client,
    ):
        client_mock = AsyncMock()
        client_mock.admin_update_user.side_effect = _admin_update_raises
        client_mock.sign_in_with_id_token.return_value = existing_session
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post(
                    "/api/v1/auth/google",
                    json={"id_token": "google-token"},
                    headers={"Authorization": f"Bearer {anon_jwt}"},
                )
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 200
    body = response.json()
    assert body["is_anonymous"] is False

    # Anon row should be abandoned (deleted_at set).
    abandoned = (await db_session.execute(select(User).where(User.id == anon.id))).scalar_one()
    assert abandoned.deleted_at is not None


@pytest.mark.asyncio
async def test_anon_to_google_post_upgrade_supabase_failure_returns_502(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    google_claims: dict[str, Any],
) -> None:
    anon_supabase_id = uuid.uuid4()
    anon = User(supabase_user_id=anon_supabase_id, anon_id=uuid.uuid4())
    db_session.add(anon)
    await db_session.flush()

    from app.auth.supabase_client import SupabaseAuthError
    from app.tests.conftest_jwt import make_supabase_jwt

    anon_jwt = make_supabase_jwt(sub=str(anon_supabase_id), is_anonymous=True)

    with (
        patch(
            "app.auth.router._verify_google_id_token",
            new=AsyncMock(return_value=google_claims),
        ),
        patch("app.auth.router._get_supabase_client") as get_client,
    ):
        client_mock = AsyncMock()
        client_mock.admin_update_user.return_value = {"id": str(anon_supabase_id)}
        client_mock.sign_in_with_id_token.side_effect = SupabaseAuthError(
            500, {"msg": "internal error"}
        )
        get_client.return_value = client_mock

        from app.db.dependencies import get_db

        async def _override_get_db() -> AsyncGenerator[AsyncSession, None]:
            yield db_session

        app.dependency_overrides[get_db] = _override_get_db
        try:
            transport = ASGITransport(app=app)
            async with AsyncClient(transport=transport, base_url="http://test") as http:
                response = await http.post(
                    "/api/v1/auth/google",
                    json={"id_token": "google-token"},
                    headers={"Authorization": f"Bearer {anon_jwt}"},
                )
        finally:
            app.dependency_overrides.clear()

    assert response.status_code == 502
    assert response.json()["reason"] == "supabase_unavailable"
    # admin_update_user succeeded, so the anon row should NOT have been abandoned —
    # the 502 surfaces the half-upgrade state to the caller for retry.
    refreshed = (await db_session.execute(select(User).where(User.id == anon.id))).scalar_one()
    assert refreshed.deleted_at is None


@pytest.mark.asyncio
async def test_refresh_returns_new_tokens(
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
) -> None:
    new_session = _supabase_session_for(uuid.uuid4(), anon=True)

    with patch("app.auth.router._get_supabase_client") as get_client:
        client_mock = AsyncMock()
        client_mock.refresh_session.return_value = new_session
        get_client.return_value = client_mock

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post("/api/v1/auth/refresh", json={"refresh_token": "old-rt"})
    assert response.status_code == 200
    assert response.json()["access_token"] == "test-access-token"


@pytest.mark.asyncio
async def test_logout_returns_ok(
    db_session: AsyncSession,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    make_jwt: Any,
) -> None:
    with patch("app.auth.router._get_supabase_client") as get_client:
        client_mock = AsyncMock()
        client_mock.sign_out.return_value = None
        get_client.return_value = client_mock

        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as http:
            response = await http.post(
                "/api/v1/auth/logout",
                headers={"Authorization": f"Bearer {make_jwt()}"},
            )
    assert response.status_code == 200
    assert response.json()["status"] == "ok"
