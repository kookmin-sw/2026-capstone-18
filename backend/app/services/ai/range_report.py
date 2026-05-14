"""RangeReportGenerator — produces arbitrary-range Korean reports via Bedrock."""

from __future__ import annotations

import json
import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, time
from statistics import fmean
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.range_report import RangeReport
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent
from app.models.user import User
from app.services.ai.bedrock_client import BedrockClient
from app.services.ai.prompts import range_report_prompt
from app.services.insights.cycle_lookup import CycleSnapshot, classify
from app.services.insights.patterns import compute_patterns

REPORT_MAX_TOKENS = 1500
_EVENTS_CAP = 50


@dataclass(frozen=True)
class GeneratedRangeReport:
    period_start: date
    period_end: date
    headline: str
    body_md: str
    takeaways: list[dict[str, Any]]


class RangeReportGenerator:
    def __init__(self, bedrock: BedrockClient | None = None) -> None:
        self._bedrock = bedrock or BedrockClient()

    async def generate(
        self,
        db: AsyncSession,
        *,
        user_id: uuid.UUID,
        period_start: date,
        period_end: date,
    ) -> GeneratedRangeReport:
        start_dt = datetime.combine(period_start, time.min, tzinfo=UTC)
        end_dt = datetime.combine(period_end, time.max, tzinfo=UTC)

        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one()
        events = (
            (
                await db.execute(
                    select(StressEvent)
                    .where(StressEvent.user_id == user_id)
                    .where(StressEvent.detected_at >= start_dt)
                    .where(StressEvent.detected_at <= end_dt)
                    .order_by(StressEvent.detected_at)
                )
            )
            .scalars()
            .all()
        )
        sleeps = (
            (
                await db.execute(
                    select(SleepLog)
                    .where(SleepLog.user_id == user_id)
                    .where(SleepLog.ended_on >= period_start)
                    .where(SleepLog.ended_on <= period_end)
                    .order_by(SleepLog.ended_on)
                )
            )
            .scalars()
            .all()
        )
        cycles_rows = (
            (await db.execute(select(Cycle).where(Cycle.user_id == user_id))).scalars().all()
        )
        classifier = classify(
            cycles=[
                CycleSnapshot(
                    period_start_date=c.period_start_date,
                    cycle_length_days=c.cycle_length_days or 28,
                    is_period_ongoing=c.is_period_ongoing,
                )
                for c in cycles_rows
            ]
        )
        period_end_dt = datetime.combine(period_end, time.max, tzinfo=UTC)
        if cycles_rows:
            phase_tuple = classifier(period_end_dt)
            current_phase = phase_tuple[0] if phase_tuple else "unknown"
        else:
            current_phase = "unknown"

        # Top patterns from existing detector, scoped to the same range.
        patterns_resp = await compute_patterns(db, user_id=user_id, frm=period_start, to=period_end)
        top_pattern_lines = [
            f"{p.category_name} · {p.phase} (+{p.delta_pct:.0f}%, {p.event_count}건)"
            for p in patterns_resp.patterns[:3]
        ]

        # Aggregate sleep.
        if sleeps:
            avg_sleep_min = int(fmean(s.total_minutes for s in sleeps))
            avg_rating = max({s.rating for s in sleeps}, key=[s.rating for s in sleeps].count)
        else:
            avg_sleep_min = 0
            avg_rating = "—"

        # Build events summary lines — cap at 50 most recent, append truncation note.
        n_events = len(events)
        display_events = events[-_EVENTS_CAP:] if n_events > _EVENTS_CAP else events
        events_summary_lines = [
            f"{ev.detected_at.strftime('%a %H:%M')} · 강도 {ev.user_stress_level or '?'}"
            + (f" · {ev.mood_chips[0]}" if ev.mood_chips else "")
            for ev in display_events
        ]
        if n_events > _EVENTS_CAP:
            events_summary_lines.append(f"… 외 {n_events - _EVENTS_CAP}건")

        sleep_lines = [f"{s.ended_on.isoformat()} {s.total_minutes}분 ({s.rating})" for s in sleeps]

        system, user_prompt = range_report_prompt(
            display_name=user.display_name or "사용자",
            period_start=period_start,
            period_end=period_end,
            n_events=n_events,
            events_summary_lines=events_summary_lines,
            n_sleep=len(sleeps),
            avg_sleep_min=avg_sleep_min,
            avg_rating=avg_rating,
            sleep_lines=sleep_lines,
            current_phase=current_phase,
            phase_changes="(미집계)",
            top_pattern_lines=top_pattern_lines,
        )

        raw = await self._bedrock.invoke(user_prompt, system=system, max_tokens=REPORT_MAX_TOKENS)
        parsed = _try_parse(raw)
        if parsed is None:
            parsed = _fallback_summary(
                n_events=n_events,
                avg_sleep_min=avg_sleep_min,
                top_pattern_lines=top_pattern_lines,
            )

        existing = (
            await db.execute(
                select(RangeReport).where(
                    RangeReport.user_id == user_id,
                    RangeReport.period_start == period_start,
                    RangeReport.period_end == period_end,
                )
            )
        ).scalar_one_or_none()
        if existing is None:
            row = RangeReport(
                user_id=user_id,
                period_start=period_start,
                period_end=period_end,
                headline=parsed["headline"],
                body_md=parsed["body_md"],
                takeaways=parsed["takeaways"],
            )
            db.add(row)
        else:
            existing.headline = parsed["headline"]
            existing.body_md = parsed["body_md"]
            existing.takeaways = parsed["takeaways"]
            existing.generated_at = datetime.now(UTC)
        await db.flush()

        return GeneratedRangeReport(
            period_start=period_start,
            period_end=period_end,
            headline=parsed["headline"],
            body_md=parsed["body_md"],
            takeaways=parsed["takeaways"],
        )


def _try_parse(raw: str) -> dict[str, Any] | None:
    text = raw.strip()
    # Strip optional ```json fences.
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
    body_md = obj.get("body_md")
    takeaways = obj.get("takeaways", [])
    if not isinstance(headline, str) or not isinstance(body_md, str):
        return None
    if not isinstance(takeaways, list):
        takeaways = []
    return {"headline": headline, "body_md": body_md, "takeaways": takeaways}


def _fallback_summary(
    *,
    n_events: int,
    avg_sleep_min: int,
    top_pattern_lines: list[str],
) -> dict[str, Any]:
    return {
        "headline": "이 기간 요약",
        "body_md": (
            f"이 기간 스트레스 이벤트는 총 {n_events}건이었고, "
            f"평균 수면 시간은 약 {avg_sleep_min}분이었습니다."
        ),
        "takeaways": [{"title": "패턴", "body": line} for line in top_pattern_lines[:3]],
    }
