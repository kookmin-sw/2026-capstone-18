"""Smoke tests for GET /api/v1/dashboard/today."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_get_dashboard_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body == {
        "stress": None,
        "sleep": None,
        "mood": None,
        "events_count_24h": 0,
        "cycle": None,
    }


@pytest.mark.asyncio
async def test_get_dashboard_with_full_state(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    now = datetime.now(tz=UTC)
    today = now.date()

    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=now - timedelta(hours=2),
            logged=True,
            user_stress_level=62,
            mood_chips=["anxious"],
        )
    )
    db_session.add(
        SleepLog(
            id=uuid.uuid4(),
            user_id=me.id,
            fell_asleep_at=datetime.combine(
                today - timedelta(days=1), datetime.min.time(), tzinfo=UTC
            )
            + timedelta(hours=23),
            woke_up_at=datetime.combine(today, datetime.min.time(), tzinfo=UTC)
            + timedelta(hours=6, minutes=48),
            ended_on=today,
            rating="okay",
        )
    )
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=today - timedelta(days=18),
            cycle_length_days=28,
        )
    )
    await db_session.flush()

    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["stress"]["level"] == 62
    assert body["stress"]["source"] == "user"
    assert body["sleep"]["rating"] == "okay"
    assert body["sleep"]["total_minutes"] > 0
    assert body["mood"] == "anxious"
    assert body["events_count_24h"] == 1
    assert body["cycle"]["phase"] == "luteal"
    assert body["cycle"]["day"] == 19
    assert body["cycle"]["days_left_in_phase"] == 10
    assert body["cycle"]["cycle_length_days"] == 28


@pytest.mark.asyncio
async def test_get_dashboard_isolated_per_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=other.id,
            detected_at=datetime.now(tz=UTC) - timedelta(hours=1),
            logged=True,
            user_stress_level=99,
        )
    )
    await db_session.flush()

    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["stress"] is None
