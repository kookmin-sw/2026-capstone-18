"""Tests for TipGenerator: cache hit / miss / regeneration after TTL."""

from __future__ import annotations

from datetime import UTC, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pattern_tip import PatternTip
from app.services.ai.tip_generator import TipGenerator


def _pattern() -> dict[str, Any]:
    return {
        "category_name": "업무",
        "phase": "luteal",
        "delta_pct": 28.0,
        "event_count": 5,
        "recent_event_lines": ["월요일 09:00 — 회의 직후"],
    }


@pytest.mark.asyncio
async def test_cache_miss_calls_bedrock_and_writes_row(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="짧은 산책으로 황체기의 긴장을 완화해 보세요.")
    gen = TipGenerator(bedrock=bedrock)

    text = await gen.get_or_generate(
        db_session,
        user_id=me.id,
        display_name="이현이",
        pattern_key="biz:luteal",
        pattern=_pattern(),
    )

    assert "산책" in text
    assert bedrock.invoke.await_count == 1
    rows = (
        (await db_session.execute(select(PatternTip).where(PatternTip.user_id == me.id)))
        .scalars()
        .all()
    )
    assert len(rows) == 1
    assert rows[0].pattern_key == "biz:luteal"


@pytest.mark.asyncio
async def test_cache_hit_returns_existing_without_invoking(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    db_session.add(
        PatternTip(
            user_id=me.id,
            pattern_key="biz:luteal",
            tip_text="기존 캐시된 팁",
            generated_at=datetime.now(UTC) - timedelta(hours=1),
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="새 팁 (사용되면 안 됨)")
    gen = TipGenerator(bedrock=bedrock)

    text = await gen.get_or_generate(
        db_session,
        user_id=me.id,
        display_name="이현이",
        pattern_key="biz:luteal",
        pattern=_pattern(),
    )

    assert text == "기존 캐시된 팁"
    bedrock.invoke.assert_not_awaited()


@pytest.mark.asyncio
async def test_expired_cache_regenerates(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    old_time = datetime.now(UTC) - timedelta(hours=25)
    db_session.add(
        PatternTip(
            user_id=me.id,
            pattern_key="biz:luteal",
            tip_text="오래된 팁",
            generated_at=old_time,
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(return_value="새로 생성된 팁")
    gen = TipGenerator(bedrock=bedrock)

    text = await gen.get_or_generate(
        db_session,
        user_id=me.id,
        display_name="이현이",
        pattern_key="biz:luteal",
        pattern=_pattern(),
    )

    assert text == "새로 생성된 팁"
    bedrock.invoke.assert_awaited_once()
