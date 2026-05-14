"""Detect (category, phase) combinations where stress runs significantly above baseline.

Returns the top 5 patterns by `delta_pct`. A pattern qualifies if:
  - delta_pct >= 15.0 (i.e. >=15% above the user's overall avg)
  - event_count >= 3 (avoid noisy single-event 'patterns')

Uncategorized events still get a pattern row keyed on category_id=None so the FE
can render "Uncategorized & Luteal +28%" if it qualifies.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import UTC, date, datetime
from statistics import fmean

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.schemas.insights import InsightsPatternsResponse, PatternCard
from app.services.insights.cycle_lookup import CycleSnapshot, classify

DELTA_THRESHOLD_PCT = 15.0
MIN_EVENT_COUNT = 3
MAX_RESULTS = 5


async def compute_patterns(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    frm: date,
    to: date,
) -> InsightsPatternsResponse:
    if frm > to:
        raise ValueError("frm must be <= to")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    cycles = (await db.execute(select(Cycle).where(Cycle.user_id == user_id))).scalars().all()
    classifier = classify(
        cycles=[
            CycleSnapshot(
                period_start_date=c.period_start_date,
                cycle_length_days=c.cycle_length_days or 28,
                is_period_ongoing=c.is_period_ongoing,
            )
            for c in cycles
        ]
    )

    cats = (
        (
            await db.execute(
                select(TriggerCategory).where(
                    TriggerCategory.user_id == user_id,
                    TriggerCategory.archived_at.is_(None),
                )
            )
        )
        .scalars()
        .all()
    )
    cat_name: dict[uuid.UUID | None, str] = {c.id: c.name for c in cats}
    cat_name[None] = "Uncategorized"

    events = (
        (
            await db.execute(
                select(StressEvent).where(
                    StressEvent.user_id == user_id,
                    StressEvent.detected_at >= start_dt,
                    StressEvent.detected_at <= end_dt,
                    StressEvent.user_stress_level.is_not(None),
                    StressEvent.logged.is_(True),
                )
            )
        )
        .scalars()
        .all()
    )

    if not events:
        return InsightsPatternsResponse(patterns=[])

    overall_avg = fmean(
        float(ev.user_stress_level) for ev in events if ev.user_stress_level is not None
    )

    # (category_id, phase) -> list[stress_level]
    buckets: dict[tuple[uuid.UUID | None, str], list[float]] = defaultdict(list)
    for ev in events:
        if ev.user_stress_level is None:
            continue
        phase, _ = classifier(ev.detected_at)
        if phase == "pre_period":
            continue
        buckets[(ev.category_id, phase)].append(float(ev.user_stress_level))

    candidates: list[PatternCard] = []
    for (cat_id, phase), levels in buckets.items():
        if len(levels) < MIN_EVENT_COUNT:
            continue
        avg = fmean(levels)
        if overall_avg <= 0:
            continue
        delta_pct = round(((avg - overall_avg) / overall_avg) * 100.0, 1)
        if delta_pct < DELTA_THRESHOLD_PCT:
            continue
        candidates.append(
            PatternCard(
                category_id=cat_id,
                category_name=cat_name.get(cat_id, "Uncategorized"),
                phase=phase,
                category_phase_avg=round(avg, 2),
                user_overall_avg=round(overall_avg, 2),
                delta_pct=delta_pct,
                event_count=len(levels),
            )
        )

    candidates.sort(key=lambda c: c.delta_pct, reverse=True)
    return InsightsPatternsResponse(patterns=candidates[:MAX_RESULTS])
