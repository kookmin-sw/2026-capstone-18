from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory


@pytest.mark.asyncio
async def test_heatmap_groups_by_category_and_phase(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.heatmap import compute_heatmap

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 5, 1),
            cycle_length_days=28,
        )
    )
    work = TriggerCategory(
        id=uuid.uuid4(),
        user_id=me.id,
        name="Work",
        color="#7C3AED",
        sort_order=0,
    )
    db_session.add(work)
    await db_session.flush()

    # Day 19 = luteal × Work × 2 events
    for _ in range(2):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
                logged=True,
                user_stress_level=70,
                category_id=work.id,
            )
        )
    # Day 3 = menstrual × Uncategorized × 1 event
    db_session.add(
        StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 5, 3, 10, tzinfo=UTC),
            logged=True,
            user_stress_level=40,
        )
    )
    await db_session.flush()

    body = await compute_heatmap(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 31),
    )

    rows = {r.category_name: r for r in body.rows}
    # All 4 phases must be returned in canonical order so the FE renders a fixed grid.
    assert [c.phase for c in rows["Work"].cells] == [
        "menstrual",
        "follicular",
        "ovulation",
        "luteal",
    ]
    work_by_phase = {c.phase: c.count for c in rows["Work"].cells}
    assert work_by_phase == {"menstrual": 0, "follicular": 0, "ovulation": 0, "luteal": 2}

    assert "Uncategorized" in rows
    unc_by_phase = {c.phase: c.count for c in rows["Uncategorized"].cells}
    assert unc_by_phase == {"menstrual": 1, "follicular": 0, "ovulation": 0, "luteal": 0}
