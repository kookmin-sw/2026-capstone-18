"""Compose the drill-down report for one (category, phase) bucket."""

from __future__ import annotations

import uuid
from collections import Counter
from datetime import UTC, date, datetime
from statistics import fmean

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.schemas.reports import (
    DrilldownEvent,
    DrilldownHeatmapDay,
    DrilldownResponse,
    DrilldownSummary,
)
from app.services.insights.cycle_lookup import CycleSnapshot, classify

_PHASE_DAY_RANGES: dict[str, tuple[int, int]] = {
    "menstrual": (1, 5),
    "follicular": (6, 13),
    "ovulation": (14, 16),
}
# luteal range is open-ended; we compute 17 .. max(cycle_length, max(observed_day))


def _phase_day_range(
    phase: str,
    *,
    cycle_length_days: int,
    max_observed_day: int | None,
) -> list[int]:
    if phase in _PHASE_DAY_RANGES:
        a, b = _PHASE_DAY_RANGES[phase]
        return list(range(a, b + 1))
    if phase == "luteal":
        end = max(cycle_length_days, max_observed_day or cycle_length_days)
        return list(range(17, max(end, 17) + 1))
    raise ValueError(f"unsupported phase: {phase!r}")


async def compute_drilldown(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    category_id: uuid.UUID | None,
    phase: str,
    frm: date,
    to: date,
) -> DrilldownResponse:
    if frm > to:
        raise ValueError("frm must be <= to")
    if phase not in {"menstrual", "follicular", "ovulation", "luteal"}:
        raise ValueError(f"unsupported phase: {phase!r}")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    # Resolve category name for the summary.
    if category_id is None:
        category_name = "Uncategorized"
        cat_cycle_default = 28
    else:
        cat = (
            await db.execute(
                select(TriggerCategory).where(
                    TriggerCategory.id == category_id,
                    TriggerCategory.user_id == user_id,
                )
            )
        ).scalar_one_or_none()
        category_name = cat.name if cat is not None else "Unknown"
        cat_cycle_default = 28

    # Cycle classifier for phase resolution.
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
    # Pick a representative cycle_length for the heatmap grid (latest cycle's length;
    # falls back to 28 if the user has no cycles yet).
    cycle_length_for_grid = (
        max(cycles, key=lambda c: c.period_start_date).cycle_length_days
        if cycles
        else cat_cycle_default
    ) or 28

    # Pull events in window matching the category filter.
    stmt = select(StressEvent).where(
        StressEvent.user_id == user_id,
        StressEvent.detected_at >= start_dt,
        StressEvent.detected_at <= end_dt,
        StressEvent.logged.is_(True),
    )
    if category_id is None:
        stmt = stmt.where(StressEvent.category_id.is_(None))
    else:
        stmt = stmt.where(StressEvent.category_id == category_id)
    events = (await db.execute(stmt)).scalars().all()

    # Bucket by phase and cycle day.
    matched: list[tuple[StressEvent, int]] = []  # (event, cycle_day)
    for ev in events:
        ph, day = classifier(ev.detected_at)
        if ph != phase:
            continue
        matched.append((ev, day))

    # Summary stats.
    levels = [float(ev.user_stress_level) for ev, _ in matched if ev.user_stress_level is not None]
    avg_stress = round(fmean(levels), 2) if levels else None

    moods: Counter[str] = Counter()
    for ev, _ in matched:
        if ev.mood_chips:
            moods[ev.mood_chips[0]] += 1
    top_mood = moods.most_common(1)[0][0] if moods else None

    day_counts: Counter[int] = Counter()
    day_levels: dict[int, list[float]] = {}
    for ev, day in matched:
        day_counts[day] += 1
        if ev.user_stress_level is not None:
            day_levels.setdefault(day, []).append(float(ev.user_stress_level))
    most_common_day = (
        sorted(day_counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0] if day_counts else None
    )

    # Heatmap grid.
    max_observed = max(day_counts.keys(), default=None)
    grid_days = _phase_day_range(
        phase,
        cycle_length_days=cycle_length_for_grid,
        max_observed_day=max_observed,
    )
    heatmap = [
        DrilldownHeatmapDay(
            day=d,
            event_count=day_counts.get(d, 0),
            avg_stress=(round(fmean(day_levels[d]), 2) if d in day_levels else None),
        )
        for d in grid_days
    ]

    # Recent events: newest 10.
    matched.sort(key=lambda kv: kv[0].detected_at, reverse=True)
    recent: list[DrilldownEvent] = []
    for ev, day in matched[:10]:
        recent.append(
            DrilldownEvent(
                id=ev.id,
                detected_at=ev.detected_at,
                cycle_day=day,
                user_stress_level=ev.user_stress_level,
                top_mood=(ev.mood_chips[0] if ev.mood_chips else None),
                log_text=ev.log_text,
            )
        )

    summary = DrilldownSummary(
        category_id=category_id,
        category_name=category_name,
        phase=phase,
        event_count=len(matched),
        avg_stress=avg_stress,
        top_mood=top_mood,
        most_common_day=most_common_day,
        frm=frm,
        to=to,
    )
    return DrilldownResponse(summary=summary, heatmap=heatmap, recent_events=recent)
