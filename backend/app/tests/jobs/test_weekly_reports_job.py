"""Test weekly_reports_job iterates only users with events."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime
from typing import Any
from unittest.mock import AsyncMock, patch

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.jobs.weekly_reports_job import run_weekly_reports_job
from app.models.stress_event import StressEvent
from app.models.weekly_report import WeeklyReport


@pytest.mark.asyncio
async def test_only_users_with_events_in_window_get_reports(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    user_with = await make_user(display_name="active")
    await make_user(display_name="dormant")

    # Use a fixed Monday so the job window is deterministic.
    # today=Monday 2026-05-11 → _last_full_week_monday → week_start=2026-05-04, week_end=2026-05-10
    fixed_today = date(2026, 5, 11)  # Monday
    event_dt = datetime(2026, 5, 7, 12, 0, tzinfo=UTC)  # Wednesday inside window

    db_session.add(
        StressEvent(
            user_id=user_with.id,
            detected_at=event_dt,
            user_stress_level=3,
            logged=True,
            notified=True,
        )
    )
    await db_session.flush()

    fake_invoke = AsyncMock(
        return_value=json.dumps(
            {
                "headline": "h",
                "body_md": "b",
                "takeaways": [],
            }
        )
    )
    with patch("app.services.ai.weekly_report.BedrockClient") as MockClient:
        MockClient.return_value.invoke = fake_invoke
        summary = await run_weekly_reports_job(db_session, today=fixed_today)

    assert summary.users_total == 1
    assert summary.reports_written == 1
    assert summary.failures == 0
    rows = (await db_session.execute(select(WeeklyReport))).scalars().all()
    assert len(rows) == 1
    assert rows[0].user_id == user_with.id
