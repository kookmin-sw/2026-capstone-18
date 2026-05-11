"""MorningTipGenerator — composes a contextual morning signal per user per day.

Inputs: last night's SleepLog, current cycle phase, top recent stress pattern.
Output: {headline, body, context_line}. Cached per (user, YYYY-MM-DD) by
reusing the PatternTip table with a synthetic key `morning:{date}` so we
avoid a fresh migration.
"""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.pattern_tip import PatternTip
from app.models.sleep_log import SleepLog
from app.services.ai.bedrock_client import BedrockClient
from app.services.ai.prompts import PHASE_KR, morning_tip_prompt
from app.services.cycle_phase import compute_phase
from app.services.insights.patterns import compute_patterns

MAX_TIP_TOKENS = 400
PATTERNS_LOOKBACK_DAYS = 30


@dataclass(frozen=True)
class MorningTip:
    headline: str
    body: str
    context_line: str | None
    pattern_key: str | None
    generated_at: datetime


class MorningTipUnavailable(Exception):
    """No usable signal to compose a tip from (no sleep, no cycle, no patterns)."""


class MorningTipGenerator:
    def __init__(self, bedrock: BedrockClient | None = None) -> None:
        self._bedrock = bedrock or BedrockClient()

    async def get_or_generate(
        self,
        db: AsyncSession,
        *,
        user_id: uuid.UUID,
        display_name: str,
        today: date | None = None,
    ) -> MorningTip:
        today = today or datetime.now(UTC).date()
        cache_key = f"morning:{today.isoformat()}"

        existing = (
            await db.execute(
                select(PatternTip).where(
                    PatternTip.user_id == user_id,
                    PatternTip.pattern_key == cache_key,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            parsed = _try_parse_payload(existing.tip_text)
            if parsed is not None:
                return MorningTip(
                    headline=parsed["headline"],
                    body=parsed["body"],
                    context_line=parsed.get("context_line"),
                    pattern_key=parsed.get("pattern_key"),
                    generated_at=existing.generated_at,
                )

        context = await _gather_context(db, user_id=user_id, today=today)
        if not context.has_any_signal():
            raise MorningTipUnavailable

        system, user_prompt = morning_tip_prompt(
            display_name=display_name,
            phase=context.phase,
            cycle_day=context.cycle_day,
            sleep_minutes=context.sleep_minutes,
            sleep_rating=context.sleep_rating,
            top_pattern_line=context.top_pattern_line(),
        )
        raw = await self._bedrock.invoke(user_prompt, system=system, max_tokens=MAX_TIP_TOKENS)
        parsed = _try_parse_payload(raw)
        if parsed is None:
            parsed = _fallback_payload(context)

        payload = {
            "headline": parsed["headline"],
            "body": parsed["body"],
            "context_line": parsed.get("context_line") or context.fallback_context_line(),
            "pattern_key": context.top_pattern_key,
        }
        serialized = json.dumps(payload, ensure_ascii=False)

        now = datetime.now(UTC)
        if existing is not None:
            existing.tip_text = serialized
            existing.generated_at = now
        else:
            db.add(
                PatternTip(
                    user_id=user_id,
                    pattern_key=cache_key,
                    tip_text=serialized,
                    generated_at=now,
                )
            )
        await db.flush()

        return MorningTip(
            headline=payload["headline"],
            body=payload["body"],
            context_line=payload["context_line"],
            pattern_key=payload["pattern_key"],
            generated_at=now,
        )


@dataclass(frozen=True)
class _MorningContext:
    phase: str
    cycle_day: int | None
    sleep_minutes: int | None
    sleep_rating: str | None
    top_pattern_label: str | None
    top_pattern_delta_pct: float | None
    top_pattern_key: str | None

    def has_any_signal(self) -> bool:
        return (
            self.sleep_minutes is not None
            or self.phase != "pre_period"
            or self.top_pattern_label is not None
        )

    def top_pattern_line(self) -> str | None:
        if self.top_pattern_label is None or self.top_pattern_delta_pct is None:
            return None
        return f"{self.top_pattern_label} (+{self.top_pattern_delta_pct:.0f}%)"

    def fallback_context_line(self) -> str:
        parts: list[str] = []
        if self.sleep_minutes is not None:
            hours, minutes = divmod(self.sleep_minutes, 60)
            parts.append(f"어젯밤 {hours}h {minutes}m")
        phase_kr = PHASE_KR.get(self.phase)
        if phase_kr:
            parts.append(phase_kr)
        return " · ".join(parts) if parts else ""


async def _gather_context(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    today: date,
) -> _MorningContext:
    sleep_minutes: int | None = None
    sleep_rating: str | None = None
    recent_sleep = (
        await db.execute(
            select(SleepLog)
            .where(
                SleepLog.user_id == user_id,
                SleepLog.ended_on >= today - timedelta(days=1),
                SleepLog.ended_on <= today,
            )
            .order_by(SleepLog.ended_on.desc(), SleepLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if recent_sleep is not None:
        sleep_minutes = int(recent_sleep.total_minutes)
        sleep_rating = recent_sleep.rating

    phase = "pre_period"
    cycle_day: int | None = None
    latest_cycle = (
        await db.execute(
            select(Cycle)
            .where(Cycle.user_id == user_id, Cycle.period_start_date <= today)
            .order_by(Cycle.period_start_date.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if latest_cycle is not None:
        length = latest_cycle.cycle_length_days or 28
        days_since = (today - latest_cycle.period_start_date).days
        if days_since <= length * 1.5:
            phase, cycle_day = compute_phase(
                today=today,
                period_start_date=latest_cycle.period_start_date,
                cycle_length_days=length,
            )

    patterns_resp = await compute_patterns(
        db,
        user_id=user_id,
        frm=today - timedelta(days=PATTERNS_LOOKBACK_DAYS),
        to=today,
    )
    top_pattern_label: str | None = None
    top_pattern_delta_pct: float | None = None
    top_pattern_key: str | None = None
    if patterns_resp.patterns:
        top = patterns_resp.patterns[0]
        top_pattern_label = f"{top.category_name} · {PHASE_KR.get(top.phase, top.phase)}"
        top_pattern_delta_pct = float(top.delta_pct)
        top_pattern_key = f"{top.category_id or 'none'}:{top.phase}"

    return _MorningContext(
        phase=phase,
        cycle_day=cycle_day,
        sleep_minutes=sleep_minutes,
        sleep_rating=sleep_rating,
        top_pattern_label=top_pattern_label,
        top_pattern_delta_pct=top_pattern_delta_pct,
        top_pattern_key=top_pattern_key,
    )


def _try_parse_payload(raw: str) -> dict[str, Any] | None:
    text = raw.strip()
    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:].lstrip()
    try:
        obj = json.loads(text)
    except json.JSONDecodeError:
        return None
    if not isinstance(obj, dict):
        return None
    headline = obj.get("headline")
    body = obj.get("body")
    if not isinstance(headline, str) or not isinstance(body, str):
        return None
    context_line = obj.get("context_line")
    if context_line is not None and not isinstance(context_line, str):
        context_line = None
    pattern_key = obj.get("pattern_key")
    if pattern_key is not None and not isinstance(pattern_key, str):
        pattern_key = None
    return {
        "headline": headline,
        "body": body,
        "context_line": context_line,
        "pattern_key": pattern_key,
    }


def _fallback_payload(context: _MorningContext) -> dict[str, Any]:
    headline = "오늘은 천천히 시작해 봐요"
    body = (
        "최근 데이터를 바탕으로 부드러운 하루를 추천드려요. "
        "짧은 산책과 한 잔의 따뜻한 음료로 시작해 보세요."
    )
    return {"headline": headline, "body": body, "context_line": context.fallback_context_line()}
