"""POST /api/v1/events."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_post_event_creates_row(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    user = await make_user()
    payload = {
        "detected_at": "2026-05-06T12:00:00+00:00",
        "model_confidence": 0.91,
        "cycle_phase": "luteal",
        "cycle_day": 22,
    }
    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(user.supabase_user_id)),
        json=payload,
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_id"] == str(user.id)
    assert body["model_confidence"] == 0.91
    assert body["logged"] is False

    row = (
        await db_session.execute(select(StressEvent).where(StressEvent.id == uuid.UUID(body["id"])))
    ).scalar_one()
    assert row.user_id == user.id


@pytest.mark.asyncio
async def test_post_event_requires_auth(client: AsyncClient) -> None:
    resp = await client.post(
        "/api/v1/events",
        json={"detected_at": "2026-05-06T12:00:00+00:00"},
    )
    assert resp.status_code == 401


@pytest.mark.asyncio
async def test_post_event_rejects_bad_confidence(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    user = await make_user()
    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(user.supabase_user_id)),
        json={
            "detected_at": "2026-05-06T12:00:00+00:00",
            "model_confidence": 1.5,
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_post_event_ignores_client_user_id(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """Even if a client puts a user_id in the body, we use the JWT's user."""
    user_a = await make_user()
    user_b = await make_user()
    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(user_a.supabase_user_id)),
        json={
            "detected_at": "2026-05-06T12:00:00+00:00",
            "user_id": str(user_b.id),
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_id"] == str(user_a.id)


@pytest.mark.asyncio
async def test_post_event_rejected_for_deleted_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    user = await make_user(deleted_at=datetime.now(tz=UTC))
    resp = await client.post(
        "/api/v1/events",
        headers=auth_headers(str(user.supabase_user_id)),
        json={"detected_at": "2026-05-06T12:00:00+00:00"},
    )
    assert resp.status_code == 403
