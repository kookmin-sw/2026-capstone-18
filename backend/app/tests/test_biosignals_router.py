"""POST /api/v1/sync/biosignals — opt-in raw biosignal upload."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.raw_biosignal_upload import RawBiosignalUpload


@pytest.mark.asyncio
async def test_biosignals_upload_requires_consent_on(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(consent_raw_biosignals=False)
    resp = await client.post(
        "/api/v1/sync/biosignals",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "signal_type": "hrv",
            "recorded_at": "2026-05-06T12:00:00+00:00",
            "byte_size": 4096,
            "content_hash": "abc",
        },
    )
    assert resp.status_code == 403
    body = resp.json()
    assert body["reason"] == "consent_required"


@pytest.mark.asyncio
async def test_biosignals_upload_returns_presigned_url_when_consent_on(
    client: AsyncClient,
    db_session: AsyncSession,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(consent_raw_biosignals=True)
    resp = await client.post(
        "/api/v1/sync/biosignals",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "signal_type": "ppg",
            "recorded_at": "2026-05-06T12:00:00+00:00",
            "byte_size": 8192,
            "content_hash": "def",
        },
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["presigned_put_url"].startswith("https://")
    assert body["s3_object_key"].startswith(f"users/{me.id}/")

    rows = (
        (
            await db_session.execute(
                select(RawBiosignalUpload).where(RawBiosignalUpload.user_id == me.id)
            )
        )
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].signal_type == "ppg"
    assert rows[0].expires_at is not None
    assert rows[0].expires_at > rows[0].recorded_at


@pytest.mark.asyncio
async def test_biosignals_upload_rejects_revoked_consent(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(
        consent_raw_biosignals=True,
        consent_revoked_at=datetime.now(tz=UTC),
    )
    resp = await client.post(
        "/api/v1/sync/biosignals",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "signal_type": "hrv",
            "recorded_at": "2026-05-06T12:00:00+00:00",
            "byte_size": 1024,
            "content_hash": "x",
        },
    )
    assert resp.status_code == 403


@pytest.mark.asyncio
async def test_biosignals_upload_rejects_unknown_signal_type(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user(consent_raw_biosignals=True)
    resp = await client.post(
        "/api/v1/sync/biosignals",
        headers=auth_headers(str(me.supabase_user_id)),
        json={
            "signal_type": "voice",
            "recorded_at": "2026-05-06T12:00:00+00:00",
            "byte_size": 1024,
            "content_hash": "x",
        },
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_biosignals_upload_requires_auth(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
) -> None:
    resp = await client.post(
        "/api/v1/sync/biosignals",
        json={
            "signal_type": "hrv",
            "recorded_at": "2026-05-06T12:00:00+00:00",
            "byte_size": 1024,
            "content_hash": "x",
        },
    )
    assert resp.status_code == 401
