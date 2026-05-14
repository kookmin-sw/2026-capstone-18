"""Tests for the nightly range-report prewarm job."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.jobs.prewarm_range_reports_job import (
    CANONICAL_RANGE_DAYS,
    run_prewarm_range_reports_job,
)
from app.models.range_report import RangeReport
from app.models.stress_event import StressEvent


def _fake_bedrock_payload() -> str:
    return json.dumps(
        {
            "headline": "test headline",
            "body_md": "body",
            "takeaways": [],
        }
    )


@pytest.mark.asyncio
async def test_active_users_get_all_canonical_ranges_warmed(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """A user with an event in the last 30d gets one row per canonical range."""
    active = await make_user(display_name="active")
    await make_user(display_name="dormant")  # no events → must be skipped

    today = date(2026, 5, 14)
    # Event 2 days ago — inside the active window
    db_session.add(
        StressEvent(
            user_id=active.id,
            detected_at=datetime(2026, 5, 12, 12, 0, tzinfo=UTC),
            user_stress_level=3,
            logged=True,
            notified=True,
        )
    )
    await db_session.flush()

    fake_invoke = AsyncMock(return_value=_fake_bedrock_payload())
    with patch("app.services.ai.range_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = fake_invoke
        summary = await run_prewarm_range_reports_job(db_session, today=today)

    assert summary.users_total == 1
    assert summary.reports_written == len(CANONICAL_RANGE_DAYS)
    assert summary.failures == 0

    rows = (
        (await db_session.execute(select(RangeReport).where(RangeReport.user_id == active.id)))
        .scalars()
        .all()
    )
    assert len(rows) == len(CANONICAL_RANGE_DAYS)
    period_starts = {r.period_start for r in rows}
    assert period_starts == {today - timedelta(days=d) for d in CANONICAL_RANGE_DAYS}


@pytest.mark.asyncio
async def test_fresh_cache_is_skipped(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """If a range_reports row is already newer than the latest event, skip it.

    Freshness compares against StressEvent.created_at (when the row was
    inserted), not detected_at. We override created_at explicitly so the test
    is not racing against wall-clock now()."""
    user = await make_user(display_name="cached")
    today = date(2026, 5, 14)

    # Event inserted on May 12 — created_at explicitly pinned so the freshness
    # check has a stable reference point.
    event_created = datetime(2026, 5, 12, 12, 0, tzinfo=UTC)
    db_session.add(
        StressEvent(
            user_id=user.id,
            detected_at=event_created,
            created_at=event_created,
            user_stress_level=3,
            logged=True,
            notified=True,
        )
    )

    # Pre-existing 7d cache row generated AFTER the event — should be skipped
    fresh_7d = RangeReport(
        user_id=user.id,
        period_start=today - timedelta(days=7),
        period_end=today,
        headline="cached",
        body_md="cached body",
        takeaways=[],
        generated_at=datetime(2026, 5, 13, 0, 0, tzinfo=UTC),  # > event_created
    )
    db_session.add(fresh_7d)
    await db_session.flush()

    fake_invoke = AsyncMock(return_value=_fake_bedrock_payload())
    with patch("app.services.ai.range_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = fake_invoke
        summary = await run_prewarm_range_reports_job(db_session, today=today)

    # 7d skipped (cache fresh), 14d + 30d written
    assert summary.reports_skipped_cache_fresh == 1
    assert summary.reports_written == len(CANONICAL_RANGE_DAYS) - 1
    assert summary.failures == 0


@pytest.mark.asyncio
async def test_stale_cache_is_regenerated(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """If an event is newer than the cached row, the row must be regenerated."""
    user = await make_user(display_name="stale")
    today = date(2026, 5, 14)

    # Stale cache row first (generated 5 days ago)
    stale = RangeReport(
        user_id=user.id,
        period_start=today - timedelta(days=7),
        period_end=today,
        headline="old",
        body_md="old body",
        takeaways=[],
        generated_at=datetime(2026, 5, 9, 0, 0, tzinfo=UTC),
    )
    db_session.add(stale)

    # NEW event after the cache was generated — created_at pinned for stability
    new_event_ts = datetime(2026, 5, 13, 9, 0, tzinfo=UTC)
    db_session.add(
        StressEvent(
            user_id=user.id,
            detected_at=new_event_ts,
            created_at=new_event_ts,
            user_stress_level=4,
            logged=True,
            notified=True,
        )
    )
    await db_session.flush()

    fake_invoke = AsyncMock(return_value=_fake_bedrock_payload())
    with patch("app.services.ai.range_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = fake_invoke
        summary = await run_prewarm_range_reports_job(db_session, today=today)

    # All 3 ranges regenerated (stale 7d + missing 14d + missing 30d)
    assert summary.reports_skipped_cache_fresh == 0
    assert summary.reports_written == len(CANONICAL_RANGE_DAYS)


@pytest.mark.asyncio
async def test_per_user_failure_is_isolated_by_savepoint(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """A Bedrock failure for one (user, range) must not roll back other writes."""
    user_a = await make_user(display_name="ok")
    user_b = await make_user(display_name="fails")
    today = date(2026, 5, 14)

    for u in (user_a, user_b):
        db_session.add(
            StressEvent(
                user_id=u.id,
                detected_at=datetime(2026, 5, 12, 12, 0, tzinfo=UTC),
                user_stress_level=3,
                logged=True,
                notified=True,
            )
        )
    await db_session.flush()

    # Fail every Bedrock call for user_b; succeed otherwise.
    async def fake_invoke_then_fail(*args: Any, **kwargs: Any) -> str:
        # Inspect the prompt-bound user; here we simulate failure based on a
        # call counter — every 4th call fails (covers all 3 ranges for user_b
        # when user_b is iterated second). Simpler: raise for user_b only.
        raise RuntimeError("bedrock unavailable")

    # Patch with a side_effect that fails for user_b and succeeds for user_a.
    call_count = {"n": 0}

    async def selective_invoke(*args: Any, **kwargs: Any) -> str:
        call_count["n"] += 1
        # First user iterated gets 3 successes, second gets 3 failures.
        if call_count["n"] <= 3:
            return _fake_bedrock_payload()
        raise RuntimeError("bedrock unavailable")

    with patch("app.services.ai.range_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = AsyncMock(side_effect=selective_invoke)
        summary = await run_prewarm_range_reports_job(db_session, today=today)

    assert summary.users_total == 2
    assert summary.reports_written == 3  # one user fully succeeded
    assert summary.failures == 3  # other user's 3 ranges all failed
    # The successful user's rows must still be in the DB after commit
    rows = (await db_session.execute(select(RangeReport))).scalars().all()
    assert len(rows) == 3


@pytest.mark.asyncio
async def test_user_id_filter_narrows_scope(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """--user-id <uuid> filter only warms the named user."""
    target = await make_user(display_name="target")
    other = await make_user(display_name="other")
    today = date(2026, 5, 14)
    event_dt = datetime(2026, 5, 12, 12, 0, tzinfo=UTC)
    for u in (target, other):
        db_session.add(
            StressEvent(
                user_id=u.id,
                detected_at=event_dt,
                user_stress_level=3,
                logged=True,
                notified=True,
            )
        )
    await db_session.flush()

    fake_invoke = AsyncMock(return_value=_fake_bedrock_payload())
    with patch("app.services.ai.range_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = fake_invoke
        summary = await run_prewarm_range_reports_job(
            db_session, today=today, user_id_filter=[str(target.id)]
        )

    assert summary.users_total == 1
    assert summary.reports_written == len(CANONICAL_RANGE_DAYS)
    rows = (await db_session.execute(select(RangeReport))).scalars().all()
    assert {r.user_id for r in rows} == {target.id}
