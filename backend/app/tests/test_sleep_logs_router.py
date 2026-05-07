"""POST/GET/PATCH/DELETE /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sleep_log import SleepLog


def _payload(ended_on: date = date(2026, 5, 7), **overrides: Any) -> dict[str, Any]:
    body: dict[str, Any] = {
        "fell_asleep_at": datetime(2026, 5, 6, 23, 30, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 7, 7, 15, tzinfo=UTC).isoformat(),
        "ended_on": ended_on.isoformat(),
        "rating": "okay",
    }
    body.update(overrides)
    return body


@pytest.mark.asyncio
async def test_post_creates_sleep_log_with_total_minutes(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/sleep-logs",
        headers=auth_headers(str(me.supabase_user_id)),
        json=_payload(),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["rating"] == "okay"
    assert body["total_minutes"] == 7 * 60 + 45  # 23:30 -> 07:15

    refreshed = (
        await db_session.execute(select(SleepLog).where(SleepLog.id == uuid.UUID(body["id"])))
    ).scalar_one()
    assert refreshed.user_id == me.id
    assert refreshed.total_minutes == 7 * 60 + 45


@pytest.mark.asyncio
async def test_post_rejects_duplicate_for_same_night(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    first = await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    assert first.status_code == 201

    dupe = await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    assert dupe.status_code == 409


@pytest.mark.asyncio
async def test_get_latest_returns_most_recent_by_ended_on(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    await client.post(
        "/api/v1/sleep-logs",
        headers=headers,
        json=_payload(ended_on=date(2026, 5, 5)),
    )
    await client.post(
        "/api/v1/sleep-logs",
        headers=headers,
        json=_payload(
            ended_on=date(2026, 5, 7),
            fell_asleep_at=datetime(2026, 5, 6, 22, tzinfo=UTC).isoformat(),
            woke_up_at=datetime(2026, 5, 7, 6, 30, tzinfo=UTC).isoformat(),
        ),
    )

    resp = await client.get("/api/v1/sleep-logs/latest", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["ended_on"] == "2026-05-07"


@pytest.mark.asyncio
async def test_get_latest_returns_204_when_empty(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/sleep-logs/latest",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_patch_updates_rating(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())).json()

    resp = await client.patch(
        f"/api/v1/sleep-logs/{created['id']}",
        headers=headers,
        json={"rating": "great"},
    )
    assert resp.status_code == 200
    assert resp.json()["rating"] == "great"


@pytest.mark.asyncio
async def test_delete_removes_log(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())).json()

    resp = await client.delete(f"/api/v1/sleep-logs/{created['id']}", headers=headers)
    assert resp.status_code == 204

    row = (
        await db_session.execute(select(SleepLog).where(SleepLog.id == uuid.UUID(created["id"])))
    ).scalar_one_or_none()
    assert row is None


@pytest.mark.asyncio
async def test_get_404_for_other_user_log(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    other_log = (
        await client.post(
            "/api/v1/sleep-logs",
            headers=auth_headers(str(other.supabase_user_id)),
            json=_payload(),
        )
    ).json()

    resp = await client.get(
        f"/api/v1/sleep-logs/{other_log['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_patch_rejects_reversed_window(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())).json()

    # Move woke_up_at to BEFORE the existing fell_asleep_at (23:30 prior day).
    resp = await client.patch(
        f"/api/v1/sleep-logs/{created['id']}",
        headers=headers,
        json={"woke_up_at": datetime(2026, 5, 6, 22, tzinfo=UTC).isoformat()},
    )
    assert resp.status_code == 422
    assert resp.json()["reason"] == "sleep_window_invalid"


@pytest.mark.asyncio
async def test_patch_rejects_window_under_60_minutes(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())).json()

    # Move woke_up_at to 30 minutes after fell_asleep_at (23:30 -> 00:00).
    resp = await client.patch(
        f"/api/v1/sleep-logs/{created['id']}",
        headers=headers,
        json={"woke_up_at": datetime(2026, 5, 7, 0, 0, tzinfo=UTC).isoformat()},
    )
    assert resp.status_code == 422
    assert resp.json()["reason"] == "sleep_window_invalid"
