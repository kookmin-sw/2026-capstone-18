"""Tests for MorningTipGenerator: cache hit/miss, fallback parse, no-signal."""

from __future__ import annotations

import json
from datetime import UTC, date, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.pattern_tip import PatternTip
from app.models.sleep_log import SleepLog
from app.services.ai.morning_tip import (
    MorningTipGenerator,
    MorningTipUnavailable,
)


async def _seed_sleep(db: AsyncSession, *, user_id: Any, ended_on: date) -> None:
    fell = datetime.combine(ended_on - timedelta(days=1), datetime.min.time(), tzinfo=UTC).replace(
        hour=23
    )
    woke = datetime.combine(ended_on, datetime.min.time(), tzinfo=UTC).replace(hour=6, minute=30)
    db.add(
        SleepLog(
            user_id=user_id,
            fell_asleep_at=fell,
            woke_up_at=woke,
            ended_on=ended_on,
            rating="good",
        )
    )
    await db.flush()


async def _seed_cycle(db: AsyncSession, *, user_id: Any, period_start: date) -> None:
    db.add(
        Cycle(
            user_id=user_id,
            period_start_date=period_start,
            cycle_length_days=28,
        )
    )
    await db.flush()


@pytest.mark.asyncio
async def test_generates_and_caches_when_sleep_present(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    today = date(2026, 5, 11)
    await _seed_sleep(db_session, user_id=me.id, ended_on=today)
    await _seed_cycle(db_session, user_id=me.id, period_start=today - timedelta(days=20))

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(
        return_value=json.dumps(
            {
                "headline": "오늘은 부드럽게",
                "body": "어젯밤 수면이 짧았으니 오전엔 가볍게 움직여 보세요.",
                "context_line": "어젯밤 7h 30m · 황체기",
            },
            ensure_ascii=False,
        )
    )
    gen = MorningTipGenerator(bedrock=bedrock)

    tip = await gen.get_or_generate(db_session, user_id=me.id, display_name="현이", today=today)

    assert tip.headline == "오늘은 부드럽게"
    assert "오전" in tip.body
    assert tip.context_line == "어젯밤 7h 30m · 황체기"
    assert bedrock.invoke.await_count == 1

    rows = (
        (await db_session.execute(select(PatternTip).where(PatternTip.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].pattern_key == f"morning:{today.isoformat()}"


@pytest.mark.asyncio
async def test_same_day_cache_hit_skips_bedrock(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    today = date(2026, 5, 11)
    cached = {
        "headline": "기존",
        "body": "기존 본문",
        "context_line": "어젯밤 6h",
        "pattern_key": None,
    }
    db_session.add(
        PatternTip(
            user_id=me.id,
            pattern_key=f"morning:{today.isoformat()}",
            tip_text=json.dumps(cached, ensure_ascii=False),
            generated_at=datetime.now(UTC),
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="never used")
    gen = MorningTipGenerator(bedrock=bedrock)

    tip = await gen.get_or_generate(db_session, user_id=me.id, display_name="현이", today=today)

    assert tip.headline == "기존"
    bedrock.invoke.assert_not_awaited()


@pytest.mark.asyncio
async def test_raises_unavailable_with_no_signal(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    today = date(2026, 5, 11)

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock()
    gen = MorningTipGenerator(bedrock=bedrock)

    with pytest.raises(MorningTipUnavailable):
        await gen.get_or_generate(db_session, user_id=me.id, display_name="현이", today=today)
    bedrock.invoke.assert_not_awaited()


@pytest.mark.asyncio
async def test_falls_back_when_llm_returns_garbage(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    today = date(2026, 5, 11)
    await _seed_sleep(db_session, user_id=me.id, ended_on=today)

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="not json at all")
    gen = MorningTipGenerator(bedrock=bedrock)

    tip = await gen.get_or_generate(db_session, user_id=me.id, display_name="현이", today=today)

    assert tip.headline
    assert tip.body
    assert tip.context_line is not None


@pytest.mark.asyncio
async def test_morning_tip_phase_respects_is_period_ongoing(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """When is_period_ongoing=True, _gather_context must return phase='menstrual'
    even when today is past the default menstrual window (day > 5)."""
    from app.services.ai.morning_tip import _gather_context

    me = await make_user()

    # Set period_start 7 days ago so today is day 8.
    # Without is_period_ongoing=True, compute_phase would return 'follicular'.
    today = datetime.now(tz=UTC).date()
    period_start = today - timedelta(days=7)

    db_session.add(
        Cycle(
            user_id=me.id,
            period_start_date=period_start,
            cycle_length_days=28,
            is_period_ongoing=True,
        )
    )
    await db_session.flush()

    ctx = await _gather_context(db_session, user_id=me.id, today=today)

    assert ctx.phase == "menstrual"
    assert ctx.cycle_day == 8
