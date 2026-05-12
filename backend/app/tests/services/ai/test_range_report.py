"""Tests for RangeReportGenerator."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.range_report import RangeReport
from app.models.stress_event import StressEvent
from app.services.ai.range_report import RangeReportGenerator


@pytest.mark.asyncio
async def test_generates_report_for_custom_range_and_writes_row(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user(display_name="이현이")
    period_start = date(2026, 4, 1)
    period_end = date(2026, 4, 30)
    db_session.add_all(
        [
            StressEvent(
                user_id=me.id,
                detected_at=datetime(2026, 4, 5, 9, 0, tzinfo=UTC),
                user_stress_level=3,
                logged=True,
                notified=True,
            ),
            StressEvent(
                user_id=me.id,
                detected_at=datetime(2026, 4, 20, 14, 0, tzinfo=UTC),
                user_stress_level=4,
                logged=True,
                notified=True,
            ),
            # Out-of-range — must NOT be counted
            StressEvent(
                user_id=me.id,
                detected_at=datetime(2026, 5, 2, 9, 0, tzinfo=UTC),
                user_stress_level=5,
                logged=True,
                notified=True,
            ),
        ]
    )
    await db_session.flush()
    captured: dict[str, str] = {}

    async def fake_invoke(prompt: str, *, system: str | None = None, max_tokens: int) -> str:
        captured["user"] = prompt
        captured["system"] = system or ""
        return json.dumps(
            {
                "headline": "4월 요약",
                "body_md": "## 요약\n안정적.",
                "takeaways": [{"title": "패턴", "body": "주중 오전."}],
            }
        )

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(side_effect=fake_invoke)
    gen = RangeReportGenerator(bedrock=bedrock)
    report = await gen.generate(
        db_session, user_id=me.id, period_start=period_start, period_end=period_end
    )
    assert report.headline == "4월 요약"
    assert report.period_start == period_start
    assert report.period_end == period_end
    assert "2건" in captured["user"]
    assert "30일간" in captured["system"]
    rows = (
        (await db_session.execute(select(RangeReport).where(RangeReport.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].period_start == period_start
    assert rows[0].period_end == period_end


@pytest.mark.asyncio
async def test_upserts_on_repeat_generate(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    period_start, period_end = date(2026, 4, 1), date(2026, 4, 7)
    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(
        return_value=json.dumps({"headline": "v1", "body_md": "first", "takeaways": []})
    )
    gen = RangeReportGenerator(bedrock=bedrock)
    await gen.generate(db_session, user_id=me.id, period_start=period_start, period_end=period_end)
    bedrock.invoke = AsyncMock(
        return_value=json.dumps({"headline": "v2", "body_md": "second", "takeaways": []})
    )
    await gen.generate(db_session, user_id=me.id, period_start=period_start, period_end=period_end)
    rows = (
        (await db_session.execute(select(RangeReport).where(RangeReport.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].headline == "v2"


@pytest.mark.asyncio
async def test_caps_events_summary_at_50_with_truncation_suffix(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    base = datetime(2026, 4, 1, 9, 0, tzinfo=UTC)
    db_session.add_all(
        [
            StressEvent(
                user_id=me.id,
                detected_at=base + timedelta(hours=i),
                user_stress_level=3,
                logged=True,
                notified=True,
            )
            for i in range(60)
        ]
    )
    await db_session.flush()
    captured: dict[str, str] = {}

    async def fake_invoke(prompt: str, *, system: str | None = None, max_tokens: int) -> str:
        captured["user"] = prompt
        return json.dumps({"headline": "x", "body_md": "y", "takeaways": []})

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(side_effect=fake_invoke)
    gen = RangeReportGenerator(bedrock=bedrock)
    await gen.generate(
        db_session, user_id=me.id, period_start=date(2026, 4, 1), period_end=date(2026, 4, 30)
    )
    assert "60건" in captured["user"]
    assert "외 10건" in captured["user"]


@pytest.mark.asyncio
async def test_falls_back_on_unparseable_bedrock_output(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="not json at all")
    gen = RangeReportGenerator(bedrock=bedrock)
    report = await gen.generate(
        db_session, user_id=me.id, period_start=date(2026, 4, 1), period_end=date(2026, 4, 7)
    )
    assert report.headline != ""
    assert report.body_md != ""
