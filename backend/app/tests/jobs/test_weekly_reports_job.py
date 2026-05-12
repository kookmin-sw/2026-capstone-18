"""Test weekly_reports_job iterates only users with events."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, date, datetime
from typing import Any
from unittest.mock import AsyncMock, MagicMock, patch

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.jobs.weekly_reports_job import _last_full_week_monday, run_weekly_reports_job
from app.models.stress_event import StressEvent
from app.models.weekly_report import WeeklyReport


@pytest.mark.parametrize(
    ("today", "expected_monday"),
    [
        # The most-recently-completed Mon-Sun week relative to `today`.
        # Week of Apr 27 - May 3 is the last full week for any day Sat May 2 - Sun May 10.
        (date(2026, 5, 4), date(2026, 4, 27)),  # Monday
        (date(2026, 5, 5), date(2026, 4, 27)),  # Tuesday
        (date(2026, 5, 6), date(2026, 4, 27)),  # Wednesday
        (date(2026, 5, 7), date(2026, 4, 27)),  # Thursday
        (date(2026, 5, 8), date(2026, 4, 27)),  # Friday
        (date(2026, 5, 9), date(2026, 4, 27)),  # Saturday — schedule fires here
        (date(2026, 5, 10), date(2026, 5, 4)),  # Sunday — week just ended today
        (date(2026, 5, 11), date(2026, 5, 4)),  # Monday after
    ],
)
def test_last_full_week_monday(today: date, expected_monday: date) -> None:
    """Lock in: function returns Monday of the most-recently-completed Mon-Sun week.

    The schedule fires Sat 17:00 UTC, so the most common path is the Saturday case.
    """
    assert _last_full_week_monday(today) == expected_monday


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


@pytest.mark.asyncio
async def test_per_user_db_failure_is_isolated_by_savepoint(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """A flush-then-raise for user B must not commit user B's row.

    Before the savepoint fix the session is left in a broken state after user B's
    flush, and the final db.commit() persists user B's partial row — wrong.
    After the fix only user A's report is committed.
    """
    user_a = await make_user(display_name="succeeds")
    user_b = await make_user(display_name="fails_after_flush")

    fixed_today = date(2026, 5, 11)
    event_dt = datetime(2026, 5, 7, 12, 0, tzinfo=UTC)

    for user in [user_a, user_b]:
        db_session.add(
            StressEvent(
                user_id=user.id,
                detected_at=event_dt,
                user_stress_level=3,
                logged=True,
                notified=True,
            )
        )
    await db_session.flush()

    async def fake_generate(db: AsyncSession, *, user_id: uuid.UUID, week_start: date) -> None:
        row = WeeklyReport(
            user_id=user_id,
            week_start=week_start,
            headline="test",
            body_md="body",
            takeaways=[],
        )
        db.add(row)
        await db.flush()
        if user_id == user_b.id:
            raise RuntimeError("simulated post-flush failure")

    mock_instance = MagicMock()
    mock_instance.generate = fake_generate

    with patch(
        "app.jobs.weekly_reports_job.WeeklyReportGenerator",
        return_value=mock_instance,
    ):
        summary = await run_weekly_reports_job(db_session, today=fixed_today)

    assert summary.users_total == 2
    assert summary.reports_written == 1
    assert summary.failures == 1

    rows = (await db_session.execute(select(WeeklyReport))).scalars().all()
    assert len(rows) == 1, (
        f"Expected only user_a's report; got {len(rows)} rows. "
        "Savepoint fix missing or not working."
    )
    assert rows[0].user_id == user_a.id
