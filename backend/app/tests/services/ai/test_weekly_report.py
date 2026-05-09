"""Tests for WeeklyReportGenerator: aggregation and JSON parsing."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent
from app.models.weekly_report import WeeklyReport
from app.services.ai.weekly_report import WeeklyReportGenerator


@pytest.mark.asyncio
async def test_generates_report_from_events_and_writes_row(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user(display_name="이현이")
    week_start = date(2026, 5, 4)  # Monday

    # Seed a couple of stress events in the week.
    base = datetime(2026, 5, 5, 9, 0, tzinfo=UTC)
    db_session.add_all(
        [
            StressEvent(
                user_id=me.id,
                detected_at=base,
                user_stress_level=3,
                logged=True,
                notified=True,
            ),
            StressEvent(
                user_id=me.id,
                detected_at=base + timedelta(days=2, hours=3),
                user_stress_level=4,
                logged=True,
                notified=True,
            ),
        ]
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(
        return_value=json.dumps(
            {
                "headline": "이번 주는 화요일이 가장 빡셌어요",
                "body_md": "## 한 주 요약\n월요일과 수요일에 스트레스가 두드러졌어요.",
                "takeaways": [
                    {"title": "패턴", "body": "화요일 오전 회의 시간 직후 스트레스 상승."},
                    {"title": "팁", "body": "회의 전에 5분 호흡 루틴을 시도해 보세요."},
                ],
            }
        )
    )
    gen = WeeklyReportGenerator(bedrock=bedrock)

    report = await gen.generate(db_session, user_id=me.id, week_start=week_start)

    assert report.headline.startswith("이번 주")
    assert "월요일" in report.body_md
    assert len(report.takeaways) == 2

    rows = (
        (await db_session.execute(select(WeeklyReport).where(WeeklyReport.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].week_start == week_start
    bedrock.invoke.assert_awaited_once()


@pytest.mark.asyncio
async def test_malformed_bedrock_json_falls_back_gracefully(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user(display_name="이현이")
    week_start = date(2026, 5, 4)
    db_session.add(
        StressEvent(
            user_id=me.id,
            detected_at=datetime(2026, 5, 5, 9, 0, tzinfo=UTC),
            user_stress_level=2,
            logged=True,
            notified=True,
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="this is not json at all")
    gen = WeeklyReportGenerator(bedrock=bedrock)

    report = await gen.generate(db_session, user_id=me.id, week_start=week_start)

    # Falls through to a deterministic fallback summary.
    assert report.headline  # non-empty
    assert report.body_md  # non-empty
    assert isinstance(report.takeaways, list)


@pytest.mark.asyncio
async def test_idempotent_upsert_for_same_week(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user(display_name="이현이")
    week_start = date(2026, 5, 4)
    db_session.add(
        StressEvent(
            user_id=me.id,
            detected_at=datetime(2026, 5, 5, 9, 0, tzinfo=UTC),
            user_stress_level=3,
            logged=True,
            notified=True,
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(
        return_value=json.dumps(
            {
                "headline": "h",
                "body_md": "b",
                "takeaways": [],
            }
        )
    )
    gen = WeeklyReportGenerator(bedrock=bedrock)

    await gen.generate(db_session, user_id=me.id, week_start=week_start)
    await gen.generate(db_session, user_id=me.id, week_start=week_start)

    rows = (
        (await db_session.execute(select(WeeklyReport).where(WeeklyReport.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1  # upsert, not duplicate
