"""Trigger-category × cycle-phase event count matrix.

Output shape: one row per (active) category plus one row for "Uncategorized" if
the user has any uncategorized events in the window. Cells always contain all
four phases in canonical order so the FE renders a fixed grid.
"""

from __future__ import annotations

import uuid
from collections import defaultdict
from datetime import UTC, date, datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.schemas.insights import (
    HeatmapCell,
    HeatmapRow,
    InsightsHeatmapResponse,
)
from app.services.insights.cycle_lookup import CycleSnapshot, classify

_PHASE_ORDER = ("menstrual", "follicular", "ovulation", "luteal")
_UNCATEGORIZED_COLOR = "#888888"


async def compute_heatmap(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    frm: date,
    to: date,
) -> InsightsHeatmapResponse:
    if frm > to:
        raise ValueError("frm must be <= to")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    cycles = (await db.execute(select(Cycle).where(Cycle.user_id == user_id))).scalars().all()
    classifier = classify(cycles=[CycleSnapshot.from_row(c) for c in cycles])

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
    cat_meta: dict[uuid.UUID | None, tuple[str, str]] = {c.id: (c.name, c.color) for c in cats}

    events = (
        await db.execute(
            select(StressEvent.category_id, StressEvent.detected_at).where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= start_dt,
                StressEvent.detected_at <= end_dt,
                StressEvent.logged.is_(True),
            )
        )
    ).all()

    # (category_id or None) → phase → count
    counts: dict[uuid.UUID | None, dict[str, int]] = defaultdict(
        lambda: dict.fromkeys(_PHASE_ORDER, 0)
    )
    saw_uncategorized = False
    for cat_id, detected_at in events:
        phase, _ = classifier(detected_at)
        if phase == "pre_period":
            continue
        counts[cat_id][phase] += 1
        if cat_id is None:
            saw_uncategorized = True

    rows: list[HeatmapRow] = []
    # Active categories first, sorted by name for stability.
    for cat_id, (name, color) in sorted(cat_meta.items(), key=lambda kv: kv[1][0]):
        cells_dict = counts.get(cat_id, dict.fromkeys(_PHASE_ORDER, 0))
        rows.append(
            HeatmapRow(
                category_id=cat_id,
                category_name=name,
                category_color=color,
                cells=[HeatmapCell(phase=p, count=cells_dict[p]) for p in _PHASE_ORDER],
            )
        )
    if saw_uncategorized:
        cells_dict = counts.get(None, dict.fromkeys(_PHASE_ORDER, 0))
        rows.append(
            HeatmapRow(
                category_id=None,
                category_name="Uncategorized",
                category_color=_UNCATEGORIZED_COLOR,
                cells=[HeatmapCell(phase=p, count=cells_dict[p]) for p in _PHASE_ORDER],
            )
        )
    return InsightsHeatmapResponse(rows=rows)
