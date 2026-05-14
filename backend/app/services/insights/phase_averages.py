"""Average stress per cycle phase across a date range.

Phase classification is done in Python (not SQL) so we reuse `compute_phase`.
The total event volume per request is small (≤ a few hundred for the demo cohort).
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
from app.schemas.insights import InsightsPhaseAveragesResponse, PhaseAverage
from app.services.insights.cycle_lookup import CycleSnapshot, classify


async def compute_phase_averages(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    frm: date,
    to: date,
) -> InsightsPhaseAveragesResponse:
    if frm > to:
        raise ValueError("frm must be <= to")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    cycles = (await db.execute(select(Cycle).where(Cycle.user_id == user_id))).scalars().all()
    classifier = classify(cycles=[CycleSnapshot.from_row(c) for c in cycles])

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

    buckets: dict[str, list[float]] = defaultdict(list)
    for ev in events:
        if ev.user_stress_level is None:
            continue
        phase, _ = classifier(ev.detected_at)
        if phase == "pre_period":
            continue  # don't show "pre_period" in the bar chart
        buckets[phase].append(float(ev.user_stress_level))

    phases: list[PhaseAverage] = []
    for phase in ("menstrual", "follicular", "ovulation", "luteal"):
        if phase not in buckets:
            continue
        vals = buckets[phase]
        phases.append(
            PhaseAverage(
                phase=phase,
                avg_stress=round(fmean(vals), 2),
                event_count=len(vals),
            )
        )
    return InsightsPhaseAveragesResponse(phases=phases)
