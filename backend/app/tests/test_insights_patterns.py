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
async def test_patterns_returns_only_significant_combinations(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.patterns import compute_patterns

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

    # 5 luteal Work events at avg 80
    for _ in range(5):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
                logged=True,
                user_stress_level=80,
                category_id=work.id,
            )
        )
    # 5 menstrual events (uncategorized) at avg 40 — drags overall avg down
    for _ in range(5):
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

    body = await compute_patterns(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 31),
    )
    # Overall avg: 60. Luteal & Work avg: 80. Delta: ((80-60)/60)*100 = 33.3%
    assert len(body.patterns) >= 1
    top = body.patterns[0]
    assert top.category_name == "Work"
    assert top.phase == "luteal"
    assert top.event_count == 5
    assert top.delta_pct >= 15.0


@pytest.mark.asyncio
async def test_patterns_excludes_below_threshold_or_low_count(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.patterns import compute_patterns

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 5, 1),
            cycle_length_days=28,
        )
    )
    cat = TriggerCategory(
        id=uuid.uuid4(),
        user_id=me.id,
        name="Family",
        color="#FF7777",
        sort_order=0,
    )
    db_session.add(cat)
    await db_session.flush()

    # Only 2 events for Family x luteal — below 3-event minimum.
    for _ in range(2):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
                logged=True,
                user_stress_level=99,
                category_id=cat.id,
            )
        )
    await db_session.flush()

    body = await compute_patterns(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 31),
    )
    assert body.patterns == []  # below event-count floor


@pytest.mark.asyncio
async def test_patterns_excludes_archived_categories(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    """An archived category should not surface in patterns even if the user
    has historical events still tagged with its UUID (shouldn't happen since
    delete_category clears category_id, but guard against drift)."""
    from datetime import UTC

    from app.services.insights.patterns import compute_patterns

    me = await make_user()
    db_session.add(
        Cycle(
            id=uuid.uuid4(),
            user_id=me.id,
            period_start_date=date(2026, 5, 1),
            cycle_length_days=28,
        )
    )
    archived_cat = TriggerCategory(
        id=uuid.uuid4(),
        user_id=me.id,
        name="Old Job",
        color="#888888",
        sort_order=0,
        archived_at=datetime(2026, 5, 10, tzinfo=UTC),
    )
    db_session.add(archived_cat)
    await db_session.flush()

    # Many luteal events that would qualify as a pattern
    for _ in range(5):
        db_session.add(
            StressEvent(
                id=uuid.uuid4(),
                user_id=me.id,
                detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
                logged=True,
                user_stress_level=80,
                category_id=archived_cat.id,
            )
        )
    # Also some baseline events to make overall_avg meaningful
    for _ in range(5):
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

    body = await compute_patterns(
        db_session,
        user_id=me.id,
        frm=date(2026, 5, 1),
        to=date(2026, 5, 31),
    )
    # The archived category should NOT have its name shown. If any pattern
    # qualifies for that category_id, it should fall back to "Uncategorized".
    names = [p.category_name for p in body.patterns]
    assert "Old Job" not in names
