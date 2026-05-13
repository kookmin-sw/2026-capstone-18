"""Cycles router."""

from __future__ import annotations

from datetime import date
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle


@pytest.mark.asyncio
async def test_post_period_start_creates_cycle(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/cycles/period-start",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_start_date": "2026-05-01", "cycle_length_days": 28},
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["user_id"] == str(me.id)
    assert body["period_start_date"] == "2026-05-01"
    assert body["cycle_length_days"] == 28
    assert body["auto_detected"] is False


@pytest.mark.asyncio
async def test_post_period_start_rejects_short_cycle_length(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.post(
        "/api/v1/cycles/period-start",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_start_date": "2026-05-01", "cycle_length_days": 5},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_get_current_returns_latest_cycle_with_phase(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    me = await make_user()
    older = Cycle(user_id=me.id, period_start_date=date(2026, 4, 1), cycle_length_days=28)
    newer = Cycle(user_id=me.id, period_start_date=date(2026, 5, 1), cycle_length_days=28)
    db_session.add_all([older, newer])
    await db_session.flush()

    # Pin "today" so the phase assertion is stable.
    from app.cycles import router as cycles_router

    monkeypatch.setattr(cycles_router, "_today", lambda: date(2026, 5, 8))

    resp = await client.get(
        "/api/v1/cycles/current",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["cycle"]["id"] == str(newer.id)
    assert body["phase"] == "follicular"
    assert body["day"] == 8


@pytest.mark.asyncio
async def test_get_current_404s_when_no_cycles(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/cycles/current",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404


@pytest.mark.asyncio
async def test_get_history_returns_user_cycles_descending(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    older = Cycle(user_id=me.id, period_start_date=date(2026, 3, 1))
    newer = Cycle(user_id=me.id, period_start_date=date(2026, 5, 1))
    foreign = Cycle(user_id=other.id, period_start_date=date(2026, 4, 1))
    db_session.add_all([older, newer, foreign])
    await db_session.flush()

    resp = await client.get(
        "/api/v1/cycles/history",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    items = resp.json()
    assert [i["id"] for i in items] == [str(newer.id), str(older.id)]


@pytest.mark.asyncio
async def test_patch_cycle_marks_user_corrected(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    cycle = Cycle(user_id=me.id, period_start_date=date(2026, 5, 1))
    db_session.add(cycle)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_start_date": "2026-05-02"},
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body["period_start_date"] == "2026-05-02"
    assert body["user_corrected"] is True

    refreshed = (await db_session.execute(select(Cycle).where(Cycle.id == cycle.id))).scalar_one()
    assert refreshed.user_corrected is True


@pytest.mark.asyncio
async def test_patch_cycle_rejects_empty_body(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    cycle = Cycle(user_id=me.id, period_start_date=date(2026, 5, 1))
    db_session.add(cycle)
    await db_session.flush()
    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_cycle_clears_period_end_date_with_explicit_null(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    cycle = Cycle(
        user_id=me.id,
        period_start_date=date(2026, 5, 10),
        period_end_date=date(2026, 5, 12),
    )
    db_session.add(cycle)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_end_date": None},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["period_end_date"] is None

    await db_session.refresh(cycle)
    assert cycle.period_end_date is None


@pytest.mark.asyncio
async def test_patch_cycle_clears_cycle_length_days_with_explicit_null(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    cycle = Cycle(
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    )
    db_session.add(cycle)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"cycle_length_days": None},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["cycle_length_days"] is None


@pytest.mark.asyncio
async def test_patch_cycle_rejects_clearing_period_start_date(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    cycle = Cycle(user_id=me.id, period_start_date=date(2026, 5, 1))
    db_session.add(cycle)
    await db_session.flush()

    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_start_date": None},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_cycle_404s_for_other_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    cycle = Cycle(user_id=other.id, period_start_date=date(2026, 5, 1))
    db_session.add(cycle)
    await db_session.flush()
    resp = await client.patch(
        f"/api/v1/cycles/{cycle.id}",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"period_start_date": "2026-05-02"},
    )
    assert resp.status_code == 404
