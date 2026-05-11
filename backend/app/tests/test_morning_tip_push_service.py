"""Unit tests for the morning-tip push sender."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any
from unittest.mock import AsyncMock

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.fcm_token import FcmToken
from app.models.sleep_log import SleepLog
from app.models.user_settings import UserSettings
from app.services.ai.bedrock_client import BedrockError
from app.services.ai.morning_tip import (
    MorningTip,
    MorningTipGenerator,
    MorningTipUnavailable,
)
from app.services.morning_tip_push import TIP_TYPE, send_morning_tips


def _today() -> date:
    return date(2026, 5, 11)


async def _seed_opted_in_user(db: AsyncSession, *, user_id: uuid.UUID) -> None:
    db.add(UserSettings(user_id=user_id, sleep_nudge_enabled=True))
    db.add(FcmToken(user_id=user_id, token=f"token-{user_id}", platform="android"))


def _stub_tip() -> MorningTip:
    return MorningTip(
        headline="오늘은 부드럽게",
        body="어젯밤 수면이 짧았어요. 오전에 가볍게 산책해 보세요.",
        context_line="어젯밤 6h · 황체기",
        pattern_key=None,
        generated_at=datetime.now(UTC),
    )


@pytest.mark.asyncio
async def test_returns_zero_when_no_candidates(db_session: AsyncSession) -> None:
    sender = _StubSender()
    generator = AsyncMock(spec=MorningTipGenerator)
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )
    assert result.candidates == 0
    assert result.sent == 0
    generator.get_or_generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_generates_and_pushes_to_opted_in_user(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    await _seed_opted_in_user(db_session, user_id=me.id)
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    generator.get_or_generate = AsyncMock(return_value=_stub_tip())

    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )

    assert result.candidates == 1
    assert result.generated == 1
    assert result.sent == 1
    assert result.skipped_no_signal == 0
    assert result.failures == 0
    assert sender.calls == [me.id]
    payload = sender.payloads[0]
    assert payload["type"] == TIP_TYPE
    assert payload["title"] == "오늘은 부드럽게"
    assert payload["date"] == _today().isoformat()


@pytest.mark.asyncio
async def test_skips_users_with_no_signal(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    await _seed_opted_in_user(db_session, user_id=me.id)
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    generator.get_or_generate = AsyncMock(side_effect=MorningTipUnavailable)

    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )

    assert result.candidates == 1
    assert result.generated == 0
    assert result.skipped_no_signal == 1
    assert result.sent == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_records_bedrock_failure_and_continues(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me1 = await make_user()
    me2 = await make_user()
    await _seed_opted_in_user(db_session, user_id=me1.id)
    await _seed_opted_in_user(db_session, user_id=me2.id)
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    generator.get_or_generate = AsyncMock(side_effect=[BedrockError("boom"), _stub_tip()])

    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )

    assert result.candidates == 2
    assert result.failures == 1
    assert result.generated == 1
    assert result.sent == 1


@pytest.mark.asyncio
async def test_skips_opted_out_user(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=False))
    db_session.add(FcmToken(user_id=me.id, token="t", platform="android"))
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )
    assert result.candidates == 0
    generator.get_or_generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_skips_users_without_fcm_token(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )
    assert result.candidates == 0
    generator.get_or_generate.assert_not_awaited()


@pytest.mark.asyncio
async def test_skips_deleted_users(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    me = await make_user(deleted_at=datetime.now(tz=UTC))
    await _seed_opted_in_user(db_session, user_id=me.id)
    await db_session.flush()

    generator = AsyncMock(spec=MorningTipGenerator)
    sender = _StubSender()
    result = await send_morning_tips(
        db_session, fcm_sender=sender, generator=generator, today=_today()
    )
    assert result.candidates == 0


@pytest.mark.asyncio
async def test_end_to_end_with_real_generator_and_cache(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """Integration: real MorningTipGenerator with mocked Bedrock; verifies cache."""
    import json

    me = await make_user()
    await _seed_opted_in_user(db_session, user_id=me.id)
    today = _today()
    fell = datetime.combine(today - timedelta(days=1), datetime.min.time(), tzinfo=UTC).replace(
        hour=23
    )
    woke = datetime.combine(today, datetime.min.time(), tzinfo=UTC).replace(hour=6)
    db_session.add(
        SleepLog(
            user_id=me.id,
            fell_asleep_at=fell,
            woke_up_at=woke,
            ended_on=today,
            rating="okay",
        )
    )
    db_session.add(
        Cycle(
            user_id=me.id,
            period_start_date=today - timedelta(days=20),
            cycle_length_days=28,
        )
    )
    await db_session.flush()

    bedrock = AsyncMock()
    bedrock.invoke = AsyncMock(
        return_value=json.dumps(
            {
                "headline": "차분히 시작해요",
                "body": "어젯밤 수면이 짧았어요. 가벼운 스트레칭을 추천해요.",
                "context_line": "어젯밤 7h · 황체기",
            },
            ensure_ascii=False,
        )
    )
    real_gen = MorningTipGenerator(bedrock=bedrock)
    sender = _StubSender()
    result = await send_morning_tips(db_session, fcm_sender=sender, generator=real_gen, today=today)
    assert result.sent == 1
    assert result.generated == 1


class _StubSender:
    def __init__(self) -> None:
        self.calls: list[uuid.UUID] = []
        self.payloads: list[dict[str, str]] = []

    async def __call__(
        self, db: AsyncSession, *, user_id: uuid.UUID, payload: dict[str, str]
    ) -> int:
        self.calls.append(user_id)
        self.payloads.append(payload)
        return 1
