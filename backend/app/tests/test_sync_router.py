"""/api/v1/sync — encrypted backup upload/download/delete."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sync_blob import SyncBlob


@pytest.mark.asyncio
async def test_sync_upload_returns_presigned_url(
    client: AsyncClient,
    db_session: AsyncSession,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/sync/upload",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"kind": "backup", "byte_size": 4096, "content_hash": "abc"},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["presigned_put_url"].startswith("https://")
    assert body["s3_object_key"].startswith(f"users/{me.id}/")

    rows = (
        (await db_session.execute(select(SyncBlob).where(SyncBlob.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].kind == "backup"
    assert rows[0].byte_size == 4096


@pytest.mark.asyncio
async def test_sync_upload_rejects_huge_byte_size(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/sync/upload",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"kind": "backup", "byte_size": 5_000_000_000, "content_hash": "abc"},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_sync_download_returns_latest_blob(
    client: AsyncClient,
    db_session: AsyncSession,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    older = SyncBlob(user_id=me.id, s3_object_key=f"users/{me.id}/old", kind="backup", byte_size=1)
    newer = SyncBlob(user_id=me.id, s3_object_key=f"users/{me.id}/new", kind="backup", byte_size=2)
    db_session.add_all([older, newer])
    await db_session.flush()

    resp = await client.get(
        "/api/v1/sync/download?kind=backup",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["blob_id"] == str(newer.id)
    assert body["presigned_get_url"].startswith("https://")


@pytest.mark.asyncio
async def test_sync_download_404s_when_no_blob(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/sync/download?kind=backup",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_sync_delete_clears_user_blobs(
    client: AsyncClient,
    db_session: AsyncSession,
    s3_mock: Any,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    s3_mock.put_object(Bucket="little-signals-sync-staging", Key=f"users/{me.id}/x", Body=b"data")
    db_session.add_all(
        [
            SyncBlob(user_id=me.id, s3_object_key=f"users/{me.id}/x", kind="backup", byte_size=4),
            SyncBlob(
                user_id=other.id, s3_object_key=f"users/{other.id}/y", kind="backup", byte_size=4
            ),
        ]
    )
    await db_session.flush()

    resp = await client.delete(
        "/api/v1/sync",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 204

    rows = (await db_session.execute(select(SyncBlob))).scalars().all()
    assert {r.user_id for r in rows} == {other.id}


@pytest.mark.asyncio
async def test_sync_endpoints_require_auth(
    client: AsyncClient,
    s3_mock: Any,  # noqa: ARG001
) -> None:
    assert (
        await client.post(
            "/api/v1/sync/upload", json={"kind": "backup", "byte_size": 1, "content_hash": "x"}
        )
    ).status_code == 401
    assert (await client.get("/api/v1/sync/download?kind=backup")).status_code == 401
    assert (await client.delete("/api/v1/sync")).status_code == 401
