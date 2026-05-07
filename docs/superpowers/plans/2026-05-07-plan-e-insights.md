# Plan E — Insights Aggregations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Power the Insight calendar, the Cycle × Stress chart, the Phase Averages bars, and the "Pattern Found" cards with five read-only aggregation endpoints.

**Architecture:** Five GET endpoints under `/api/v1/insights`, each backed by a small pure function in `app/services/insights/` so heavy SQL stays out of the router and unit tests can hit the math without a DB. All endpoints are read-only and require no new migrations — we aggregate over `stress_events`, `cycles`, `trigger_categories` (Plan B). Phase classification reuses `compute_phase` from Plan A's `services/cycle_phase.py`.

**Tech Stack:** Python 3.12, FastAPI 0.136, SQLAlchemy 2.0 async, Pydantic v2, Postgres 15.

---

## Decisions Locked

- All five endpoints accept the caller's JWT and **only ever return the caller's data**. No admin variant.
- Date range parameters are inclusive on both ends; default to "the latest 30 days" if omitted (`/trends`, `/phase-averages`, `/heatmap`, `/patterns`).
- `/insights/calendar` is parameterised by `month=YYYY-MM` rather than a free range, because the UI is a fixed-grid month view.
- Per-day stress is the **average of `user_stress_level`** for events on that day. Days with only model-detected (un-logged) events return null — model confidence is too noisy for a public chart.
- Phase classification for an event uses the cycle that was *active on its `detected_at`*. We resolve this with one Python pass over the user's cycles, not via per-row joins, because the user usually has fewer than ~30 cycles total.
- Patterns: a (category, phase) pair shows up if its average user_stress_level is ≥15% higher than the user's overall average AND it has ≥3 events in the window. Top 5 by `% delta` are returned. (Threshold is a constant we can tune later — no settings table needed for v1.)
- No caching. Read patterns on every request. The DB volume is small (≤100 events/user/month) and Postgres handles all five queries in <50ms cold for the demo cohort.

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `backend/app/schemas/insights.py` | **Create** | Wire DTOs for all 5 responses |
| `backend/app/services/insights/__init__.py` | **Create** | Package marker |
| `backend/app/services/insights/cycle_lookup.py` | **Create** | Build per-user cycle index → phase classifier |
| `backend/app/services/insights/calendar.py` | **Create** | Month grid: per-day phase + event intensity |
| `backend/app/services/insights/trends.py` | **Create** | Per-day avg stress |
| `backend/app/services/insights/phase_averages.py` | **Create** | Avg stress per phase across the range |
| `backend/app/services/insights/heatmap.py` | **Create** | (category × phase) event counts |
| `backend/app/services/insights/patterns.py` | **Create** | Compare phase-category avg vs overall avg, threshold |
| `backend/app/insights/__init__.py` | **Create** | Package marker |
| `backend/app/insights/router.py` | **Create** | 5 GET endpoints |
| `backend/app/main.py` | **Modify** | Wire the router |
| `backend/app/tests/test_insights_cycle_lookup.py` | **Create** | Pure-function tests |
| `backend/app/tests/test_insights_router.py` | **Create** | End-to-end tests, all 5 endpoints |

---

## Task 1: Cycle classifier (pure function)

The single most important helper across the next 4 services: given an event's `detected_at`, return the cycle phase that was active. Build it once, test it thoroughly, reuse everywhere.

**Files:**
- Create: `backend/app/services/insights/__init__.py`
- Create: `backend/app/services/insights/cycle_lookup.py`
- Create: `backend/app/tests/test_insights_cycle_lookup.py`

- [ ] **Step 1: Empty package marker**

```bash
mkdir -p backend/app/services/insights
touch backend/app/services/insights/__init__.py
```

- [ ] **Step 2: Failing unit tests**

`backend/app/tests/test_insights_cycle_lookup.py`:

```python
"""Pure-function tests for the cycle classifier."""

from __future__ import annotations

from datetime import date, datetime, UTC

import pytest


def test_classify_returns_pre_period_when_no_cycles_yet() -> None:
    from app.services.insights.cycle_lookup import classify

    classifier = classify(cycles=[])
    assert classifier(datetime(2026, 5, 6, 12, tzinfo=UTC)) == ("pre_period", 0)


def test_classify_uses_latest_cycle_before_event() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    # May 7 is day 7 of cycle starting May 1 → follicular
    phase, day = classifier(datetime(2026, 5, 7, 12, tzinfo=UTC))
    assert phase == "follicular"
    assert day == 7


def test_classify_for_event_before_first_known_period() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28)]
    classifier = classify(cycles=cycles)
    phase, day = classifier(datetime(2026, 4, 15, 12, tzinfo=UTC))
    assert phase == "pre_period"
    assert day == 0


def test_classify_picks_correct_cycle_when_event_falls_after_two_starts() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 4, 29), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    # April 28 must use the earlier cycle, not the next one starting April 29.
    phase, day = classifier(datetime(2026, 4, 28, 12, tzinfo=UTC))
    assert phase == "luteal"
    assert day == 28


def test_classify_handles_unsorted_input() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 3, 1), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    phase, day = classifier(datetime(2026, 4, 5, 12, tzinfo=UTC))
    assert phase == "menstrual"
    assert day == 5
```

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
poetry run pytest app/tests/test_insights_cycle_lookup.py -v
```

Expected: FAIL — module doesn't exist.

- [ ] **Step 3: Implement classifier**

`backend/app/services/insights/cycle_lookup.py`:

```python
"""Build a per-user cycle index → classifier mapping.

We resolve an event's phase by finding the latest period start ≤ the event's
date and applying compute_phase against it.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
from typing import Callable

from app.services.cycle_phase import compute_phase


@dataclass(frozen=True)
class CycleSnapshot:
    period_start_date: date
    cycle_length_days: int


PhaseTuple = tuple[str, int]


def classify(*, cycles: list[CycleSnapshot]) -> Callable[[datetime], PhaseTuple]:
    """Return a function that maps a datetime → (phase, day).

    The returned function is pure. It captures `cycles` sorted descending by
    period_start_date; lookup is O(n) but n is small (≤30 typical).
    """
    sorted_cycles = sorted(
        cycles, key=lambda c: c.period_start_date, reverse=True
    )

    def _classify(at: datetime) -> PhaseTuple:
        target = at.date()
        for cyc in sorted_cycles:
            if cyc.period_start_date <= target:
                return compute_phase(
                    today=target,
                    period_start_date=cyc.period_start_date,
                    cycle_length_days=cyc.cycle_length_days or 28,
                )
        return ("pre_period", 0)

    return _classify
```

- [ ] **Step 4: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_cycle_lookup.py -v
poetry run mypy app/services/insights/cycle_lookup.py
git add app/services/insights app/tests/test_insights_cycle_lookup.py
git commit -m "feat(insights): cycle phase classifier helper"
```

---

## Task 2: Schemas for all 5 endpoints

Locking the wire shape early lets the FE team start integrating against typed examples while the services come online.

**Files:**
- Create: `backend/app/schemas/insights.py`

- [ ] **Step 1: Failing schema smoke test**

`backend/app/tests/test_insights_schemas.py`:

```python
from __future__ import annotations

from datetime import date


def test_calendar_response_has_days_array() -> None:
    from app.schemas.insights import CalendarDay, InsightsCalendarResponse

    body = InsightsCalendarResponse.model_validate({
        "month": "2026-05",
        "days": [
            {"date": date(2026, 5, 1).isoformat(), "phase": "menstrual",
             "event_count": 0, "avg_stress": None},
        ],
    })
    assert body.days[0].phase == "menstrual"
    assert isinstance(body.days[0], CalendarDay)


def test_trends_response_has_series() -> None:
    from app.schemas.insights import InsightsTrendsResponse

    body = InsightsTrendsResponse.model_validate({
        "points": [{"date": "2026-05-01", "avg_stress": 42.0, "event_count": 2}],
    })
    assert body.points[0].avg_stress == 42.0


def test_phase_averages_returns_four_phases_or_subset() -> None:
    from app.schemas.insights import InsightsPhaseAveragesResponse

    body = InsightsPhaseAveragesResponse.model_validate({
        "phases": [
            {"phase": "menstrual", "avg_stress": 32.0, "event_count": 3},
            {"phase": "luteal", "avg_stress": 78.0, "event_count": 12},
        ],
    })
    assert {p.phase for p in body.phases} == {"menstrual", "luteal"}


def test_heatmap_returns_cells_with_counts() -> None:
    from app.schemas.insights import InsightsHeatmapResponse

    body = InsightsHeatmapResponse.model_validate({
        "rows": [
            {
                "category_id": "00000000-0000-0000-0000-000000000001",
                "category_name": "Work",
                "category_color": "#7C3AED",
                "cells": [
                    {"phase": "menstrual", "count": 2},
                    {"phase": "luteal", "count": 12},
                ],
            },
        ],
    })
    assert body.rows[0].category_name == "Work"


def test_patterns_returns_cards() -> None:
    from app.schemas.insights import InsightsPatternsResponse

    body = InsightsPatternsResponse.model_validate({
        "patterns": [
            {
                "category_id": "00000000-0000-0000-0000-000000000001",
                "category_name": "Work",
                "phase": "luteal",
                "category_phase_avg": 74.0,
                "user_overall_avg": 53.0,
                "delta_pct": 39.6,
                "event_count": 12,
            }
        ],
    })
    assert body.patterns[0].delta_pct > 0
```

```bash
poetry run pytest app/tests/test_insights_schemas.py -v
```

Expected: FAIL.

- [ ] **Step 2: Create schemas**

`backend/app/schemas/insights.py`:

```python
"""Wire schemas for /api/v1/insights/*."""

from __future__ import annotations

import uuid
from datetime import date

from pydantic import BaseModel, ConfigDict


class CalendarDay(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    date: date
    phase: str  # one of menstrual / follicular / ovulation / luteal / pre_period
    event_count: int
    avg_stress: float | None


class InsightsCalendarResponse(BaseModel):
    month: str  # "YYYY-MM"
    days: list[CalendarDay]


class TrendPoint(BaseModel):
    date: date
    avg_stress: float | None
    event_count: int


class InsightsTrendsResponse(BaseModel):
    points: list[TrendPoint]


class PhaseAverage(BaseModel):
    phase: str
    avg_stress: float
    event_count: int


class InsightsPhaseAveragesResponse(BaseModel):
    phases: list[PhaseAverage]


class HeatmapCell(BaseModel):
    phase: str
    count: int


class HeatmapRow(BaseModel):
    category_id: uuid.UUID | None
    category_name: str  # "Uncategorized" if category_id is None
    category_color: str  # "#888888" sentinel for Uncategorized
    cells: list[HeatmapCell]


class InsightsHeatmapResponse(BaseModel):
    rows: list[HeatmapRow]


class PatternCard(BaseModel):
    category_id: uuid.UUID | None
    category_name: str
    phase: str
    category_phase_avg: float
    user_overall_avg: float
    delta_pct: float
    event_count: int


class InsightsPatternsResponse(BaseModel):
    patterns: list[PatternCard]
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_schemas.py -v
poetry run mypy app/schemas/insights.py
git add app/schemas/insights.py app/tests/test_insights_schemas.py
git commit -m "feat(schemas): insights response DTOs"
```

---

## Task 3: Calendar service

**Files:**
- Create: `backend/app/services/insights/calendar.py`
- Create: `backend/app/tests/test_insights_calendar.py`

- [ ] **Step 1: Failing tests**

`backend/app/tests/test_insights_calendar.py`:

```python
from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_calendar_for_empty_user_returns_full_month_grid(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    assert body.month == "2026-05"
    assert len(body.days) == 31  # May has 31 days
    assert all(d.event_count == 0 and d.avg_stress is None for d in body.days)
    assert all(d.phase == "pre_period" for d in body.days)


@pytest.mark.asyncio
async def test_calendar_overlays_phase_from_cycle(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    ))
    await db_session.flush()

    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    by_day = {d.date.day: d.phase for d in body.days}
    assert by_day[1] == "menstrual"   # day 1
    assert by_day[5] == "menstrual"   # day 5
    assert by_day[6] == "follicular"  # day 6
    assert by_day[14] == "ovulation"  # day 14
    assert by_day[17] == "luteal"     # day 17


@pytest.mark.asyncio
async def test_calendar_aggregates_event_counts_and_avg(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.calendar import compute_calendar

    me = await make_user()
    for level in (40, 80):
        db_session.add(StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 5, 14, 10, tzinfo=UTC),
            logged=True,
            user_stress_level=level,
        ))
    await db_session.flush()

    body = await compute_calendar(db_session, user_id=me.id, month="2026-05")
    day14 = next(d for d in body.days if d.date.day == 14)
    assert day14.event_count == 2
    assert day14.avg_stress == 60.0  # (40 + 80) / 2
```

```bash
poetry run pytest app/tests/test_insights_calendar.py -v
```

Expected: FAIL.

- [ ] **Step 2: Implement service**

`backend/app/services/insights/calendar.py`:

```python
"""Per-month calendar grid: phase + event counts + avg user_stress_level."""

from __future__ import annotations

import calendar as _cal
import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent
from app.schemas.insights import CalendarDay, InsightsCalendarResponse
from app.services.insights.cycle_lookup import CycleSnapshot, classify


async def compute_calendar(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    month: str,  # "YYYY-MM"
) -> InsightsCalendarResponse:
    year_str, month_str = month.split("-")
    year = int(year_str)
    mo = int(month_str)
    if not (1 <= mo <= 12):
        raise ValueError(f"month out of range: {month!r}")

    last_day = _cal.monthrange(year, mo)[1]
    first = date(year, mo, 1)
    last = date(year, mo, last_day)
    start_dt = datetime.combine(first, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(last, datetime.max.time(), tzinfo=UTC)

    # Cycle index for phase classification.
    cycles = (
        await db.execute(
            select(Cycle).where(Cycle.user_id == user_id)
        )
    ).scalars().all()
    classifier = classify(cycles=[
        CycleSnapshot(
            period_start_date=c.period_start_date,
            cycle_length_days=c.cycle_length_days or 28,
        )
        for c in cycles
    ])

    # Aggregate events by day.
    day_col = func.date_trunc("day", StressEvent.detected_at).label("day")
    stmt = (
        select(
            day_col,
            func.count(StressEvent.id).label("event_count"),
            func.avg(StressEvent.user_stress_level).label("avg_stress"),
        )
        .where(
            StressEvent.user_id == user_id,
            StressEvent.detected_at >= start_dt,
            StressEvent.detected_at <= end_dt,
        )
        .group_by(day_col)
    )
    rows = (await db.execute(stmt)).all()
    by_day: dict[date, tuple[int, float | None]] = {}
    for day_dt, count, avg in rows:
        d = day_dt.date() if hasattr(day_dt, "date") else day_dt
        by_day[d] = (int(count), float(avg) if avg is not None else None)

    days: list[CalendarDay] = []
    cur = first
    while cur <= last:
        phase, _ = classifier(datetime.combine(cur, datetime.min.time(), tzinfo=UTC))
        count, avg = by_day.get(cur, (0, None))
        days.append(CalendarDay(date=cur, phase=phase, event_count=count, avg_stress=avg))
        cur = cur + timedelta(days=1)

    return InsightsCalendarResponse(month=month, days=days)
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_calendar.py -v
poetry run mypy app/services/insights/calendar.py
git add app/services/insights/calendar.py app/tests/test_insights_calendar.py
git commit -m "feat(insights): /calendar month grid service"
```

---

## Task 4: Trends + phase averages services

These two share enough SQL that they're fastest written together. Each gets its own pure async function and unit test.

**Files:**
- Create: `backend/app/services/insights/trends.py`
- Create: `backend/app/services/insights/phase_averages.py`
- Create: `backend/app/tests/test_insights_trends_phases.py`

- [ ] **Step 1: Failing tests**

`backend/app/tests/test_insights_trends_phases.py`:

```python
from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_trends_returns_per_day_avg(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.trends import compute_trends

    me = await make_user()
    base = datetime(2026, 5, 1, 9, tzinfo=UTC)
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=base, logged=True, user_stress_level=40))
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=base, logged=True, user_stress_level=80))
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=base + timedelta(days=2),
                                logged=True, user_stress_level=50))
    await db_session.flush()

    body = await compute_trends(
        db_session, user_id=me.id, frm=date(2026, 5, 1), to=date(2026, 5, 7),
    )
    by_day = {p.date: (p.avg_stress, p.event_count) for p in body.points}
    assert by_day[date(2026, 5, 1)] == (60.0, 2)
    assert by_day[date(2026, 5, 3)] == (50.0, 1)


@pytest.mark.asyncio
async def test_phase_averages_groups_by_phase(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.insights.phase_averages import compute_phase_averages

    me = await make_user()
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    ))
    # Day 2 → menstrual: 40
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=datetime(2026, 5, 2, 10, tzinfo=UTC),
                                logged=True, user_stress_level=40))
    # Day 19 → luteal: 70 and 90
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
                                logged=True, user_stress_level=70))
    db_session.add(StressEvent(id=uuid.uuid4(), user_id=me.id,
                                detected_at=datetime(2026, 5, 19, 12, tzinfo=UTC),
                                logged=True, user_stress_level=90))
    await db_session.flush()

    body = await compute_phase_averages(
        db_session, user_id=me.id,
        frm=date(2026, 5, 1), to=date(2026, 5, 31),
    )
    by_phase = {p.phase: p for p in body.phases}
    assert by_phase["menstrual"].avg_stress == 40.0
    assert by_phase["menstrual"].event_count == 1
    assert by_phase["luteal"].avg_stress == 80.0
    assert by_phase["luteal"].event_count == 2
```

```bash
poetry run pytest app/tests/test_insights_trends_phases.py -v
```

Expected: FAIL.

- [ ] **Step 2: Implement trends**

`backend/app/services/insights/trends.py`:

```python
"""Per-day average stress over a date range."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.stress_event import StressEvent
from app.schemas.insights import InsightsTrendsResponse, TrendPoint


async def compute_trends(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
    frm: date,
    to: date,
) -> InsightsTrendsResponse:
    if frm > to:
        raise ValueError("frm must be <= to")

    start_dt = datetime.combine(frm, datetime.min.time(), tzinfo=UTC)
    end_dt = datetime.combine(to, datetime.max.time(), tzinfo=UTC)

    day_col = func.date_trunc("day", StressEvent.detected_at).label("day")
    stmt = (
        select(
            day_col,
            func.count(StressEvent.id).label("event_count"),
            func.avg(StressEvent.user_stress_level).label("avg_stress"),
        )
        .where(
            StressEvent.user_id == user_id,
            StressEvent.detected_at >= start_dt,
            StressEvent.detected_at <= end_dt,
        )
        .group_by(day_col)
    )
    rows = (await db.execute(stmt)).all()
    by_day: dict[date, tuple[int, float | None]] = {}
    for day_dt, count, avg in rows:
        d = day_dt.date() if hasattr(day_dt, "date") else day_dt
        by_day[d] = (int(count), float(avg) if avg is not None else None)

    points: list[TrendPoint] = []
    cur = frm
    while cur <= to:
        count, avg = by_day.get(cur, (0, None))
        points.append(TrendPoint(date=cur, avg_stress=avg, event_count=count))
        cur += timedelta(days=1)

    return InsightsTrendsResponse(points=points)
```

- [ ] **Step 3: Implement phase averages**

`backend/app/services/insights/phase_averages.py`:

```python
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

    cycles = (
        await db.execute(
            select(Cycle).where(Cycle.user_id == user_id)
        )
    ).scalars().all()
    classifier = classify(cycles=[
        CycleSnapshot(
            period_start_date=c.period_start_date,
            cycle_length_days=c.cycle_length_days or 28,
        )
        for c in cycles
    ])

    events = (
        await db.execute(
            select(StressEvent).where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= start_dt,
                StressEvent.detected_at <= end_dt,
                StressEvent.user_stress_level.is_not(None),
            )
        )
    ).scalars().all()

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
        phases.append(PhaseAverage(
            phase=phase,
            avg_stress=round(fmean(vals), 2),
            event_count=len(vals),
        ))
    return InsightsPhaseAveragesResponse(phases=phases)
```

- [ ] **Step 4: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_trends_phases.py -v
poetry run mypy app/services/insights/trends.py app/services/insights/phase_averages.py
git add app/services/insights/trends.py app/services/insights/phase_averages.py app/tests/test_insights_trends_phases.py
git commit -m "feat(insights): trends + phase_averages services"
```

---

## Task 5: Heatmap service

**Files:**
- Create: `backend/app/services/insights/heatmap.py`
- Create: `backend/app/tests/test_insights_heatmap.py`

- [ ] **Step 1: Failing test**

`backend/app/tests/test_insights_heatmap.py`:

```python
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
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    ))
    work = TriggerCategory(
        id=uuid.uuid4(), user_id=me.id, name="Work", color="#7C3AED", sort_order=0,
    )
    db_session.add(work)
    await db_session.flush()

    # Day 19 = luteal × Work × 2 events
    for _ in range(2):
        db_session.add(StressEvent(
            id=uuid.uuid4(), user_id=me.id,
            detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
            logged=True, user_stress_level=70,
            category_id=work.id,
        ))
    # Day 3 = menstrual × Uncategorized × 1 event
    db_session.add(StressEvent(
        id=uuid.uuid4(), user_id=me.id,
        detected_at=datetime(2026, 5, 3, 10, tzinfo=UTC),
        logged=True, user_stress_level=40,
    ))
    await db_session.flush()

    body = await compute_heatmap(
        db_session, user_id=me.id,
        frm=date(2026, 5, 1), to=date(2026, 5, 31),
    )

    # Look up by category name for stable assertions.
    rows = {r.category_name: r for r in body.rows}
    # Service must return all 4 phases in canonical order so the FE renders
    # a fixed grid; check the cell list shape rather than just one cell.
    assert [c.phase for c in rows["Work"].cells] == [
        "menstrual", "follicular", "ovulation", "luteal",
    ]
    work_by_phase = {c.phase: c.count for c in rows["Work"].cells}
    assert work_by_phase == {"menstrual": 0, "follicular": 0, "ovulation": 0, "luteal": 2}

    assert "Uncategorized" in rows
    unc_by_phase = {c.phase: c.count for c in rows["Uncategorized"].cells}
    assert unc_by_phase == {"menstrual": 1, "follicular": 0, "ovulation": 0, "luteal": 0}
```

```bash
poetry run pytest app/tests/test_insights_heatmap.py -v
```

Expected: FAIL.

- [ ] **Step 2: Implement heatmap**

`backend/app/services/insights/heatmap.py`:

```python
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

    cycles = (
        await db.execute(
            select(Cycle).where(Cycle.user_id == user_id)
        )
    ).scalars().all()
    classifier = classify(cycles=[
        CycleSnapshot(
            period_start_date=c.period_start_date,
            cycle_length_days=c.cycle_length_days or 28,
        )
        for c in cycles
    ])

    cats = (
        await db.execute(
            select(TriggerCategory).where(
                TriggerCategory.user_id == user_id,
                TriggerCategory.archived_at.is_(None),
            )
        )
    ).scalars().all()
    cat_meta: dict[uuid.UUID | None, tuple[str, str]] = {
        c.id: (c.name, c.color) for c in cats
    }

    events = (
        await db.execute(
            select(StressEvent.category_id, StressEvent.detected_at).where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= start_dt,
                StressEvent.detected_at <= end_dt,
            )
        )
    ).all()

    # (category_id or None) → phase → count
    counts: dict[uuid.UUID | None, dict[str, int]] = defaultdict(
        lambda: {p: 0 for p in _PHASE_ORDER}
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
        cells_dict = counts.get(cat_id, {p: 0 for p in _PHASE_ORDER})
        rows.append(HeatmapRow(
            category_id=cat_id,
            category_name=name,
            category_color=color,
            cells=[HeatmapCell(phase=p, count=cells_dict[p]) for p in _PHASE_ORDER],
        ))
    if saw_uncategorized:
        cells_dict = counts.get(None, {p: 0 for p in _PHASE_ORDER})
        rows.append(HeatmapRow(
            category_id=None,
            category_name="Uncategorized",
            category_color=_UNCATEGORIZED_COLOR,
            cells=[HeatmapCell(phase=p, count=cells_dict[p]) for p in _PHASE_ORDER],
        ))
    return InsightsHeatmapResponse(rows=rows)
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_heatmap.py -v
poetry run mypy app/services/insights/heatmap.py
git add app/services/insights/heatmap.py app/tests/test_insights_heatmap.py
git commit -m "feat(insights): heatmap service (category x phase counts)"
```

---

## Task 6: Patterns service

The `Pattern Found` cards on the My Report screen surface category-phase combinations where the user's stress is significantly above their baseline.

**Files:**
- Create: `backend/app/services/insights/patterns.py`
- Create: `backend/app/tests/test_insights_patterns.py`

- [ ] **Step 1: Failing test**

`backend/app/tests/test_insights_patterns.py`:

```python
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
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    ))
    work = TriggerCategory(
        id=uuid.uuid4(), user_id=me.id, name="Work", color="#7C3AED", sort_order=0,
    )
    db_session.add(work)

    # 5 luteal Work events at avg 80
    for _ in range(5):
        db_session.add(StressEvent(
            id=uuid.uuid4(), user_id=me.id,
            detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
            logged=True, user_stress_level=80,
            category_id=work.id,
        ))
    # 5 menstrual events (uncategorized) at avg 40 — drags overall avg down
    for _ in range(5):
        db_session.add(StressEvent(
            id=uuid.uuid4(), user_id=me.id,
            detected_at=datetime(2026, 5, 3, 10, tzinfo=UTC),
            logged=True, user_stress_level=40,
        ))
    await db_session.flush()

    body = await compute_patterns(
        db_session, user_id=me.id,
        frm=date(2026, 5, 1), to=date(2026, 5, 31),
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
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    ))
    cat = TriggerCategory(
        id=uuid.uuid4(), user_id=me.id, name="Family", color="#FF7777", sort_order=0,
    )
    db_session.add(cat)

    # Only 2 events for Family x luteal — below 3-event minimum.
    for _ in range(2):
        db_session.add(StressEvent(
            id=uuid.uuid4(), user_id=me.id,
            detected_at=datetime(2026, 5, 19, 10, tzinfo=UTC),
            logged=True, user_stress_level=99,
            category_id=cat.id,
        ))
    await db_session.flush()

    body = await compute_patterns(
        db_session, user_id=me.id,
        frm=date(2026, 5, 1), to=date(2026, 5, 31),
    )
    assert body.patterns == []  # below event-count floor
```

```bash
poetry run pytest app/tests/test_insights_patterns.py -v
```

Expected: FAIL.

- [ ] **Step 2: Implement patterns**

`backend/app/services/insights/patterns.py`:

```python
"""Detect (category, phase) combinations where stress runs significantly above baseline.

Returns the top 5 patterns by `delta_pct`. A pattern qualifies if:
  - delta_pct >= 15.0 (i.e. ≥15% above the user's overall avg)
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
_UNCATEGORIZED_COLOR = "#888888"


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

    cycles = (
        await db.execute(
            select(Cycle).where(Cycle.user_id == user_id)
        )
    ).scalars().all()
    classifier = classify(cycles=[
        CycleSnapshot(
            period_start_date=c.period_start_date,
            cycle_length_days=c.cycle_length_days or 28,
        )
        for c in cycles
    ])

    cats = (
        await db.execute(
            select(TriggerCategory).where(TriggerCategory.user_id == user_id)
        )
    ).scalars().all()
    cat_name: dict[uuid.UUID | None, str] = {c.id: c.name for c in cats}
    cat_name[None] = "Uncategorized"

    events = (
        await db.execute(
            select(StressEvent).where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= start_dt,
                StressEvent.detected_at <= end_dt,
                StressEvent.user_stress_level.is_not(None),
            )
        )
    ).scalars().all()

    if not events:
        return InsightsPatternsResponse(patterns=[])

    overall_avg = fmean(float(ev.user_stress_level) for ev in events
                       if ev.user_stress_level is not None)

    # (category_id, phase) → list[stress_level]
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
        candidates.append(PatternCard(
            category_id=cat_id,
            category_name=cat_name.get(cat_id, "Uncategorized"),
            phase=phase,
            category_phase_avg=round(avg, 2),
            user_overall_avg=round(overall_avg, 2),
            delta_pct=delta_pct,
            event_count=len(levels),
        ))

    candidates.sort(key=lambda c: c.delta_pct, reverse=True)
    return InsightsPatternsResponse(patterns=candidates[:MAX_RESULTS])
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_insights_patterns.py -v
poetry run mypy app/services/insights/patterns.py
git add app/services/insights/patterns.py app/tests/test_insights_patterns.py
git commit -m "feat(insights): patterns service with delta-pct + min-count thresholds"
```

---

## Task 7: Insights router

**Files:**
- Create: `backend/app/insights/__init__.py`
- Create: `backend/app/insights/router.py`
- Modify: `backend/app/main.py`
- Create: `backend/app/tests/test_insights_router.py`

- [ ] **Step 1: Empty package**

```bash
mkdir -p backend/app/insights
touch backend/app/insights/__init__.py
```

- [ ] **Step 2: Failing router smoke tests**

`backend/app/tests/test_insights_router.py`:

```python
"""End-to-end smoke for /api/v1/insights/*."""

from __future__ import annotations

from datetime import date
from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_calendar_endpoint_smokes_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/calendar?month=2026-05",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["month"] == "2026-05"
    assert len(body["days"]) == 31


@pytest.mark.asyncio
async def test_calendar_rejects_bad_month(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/calendar?month=2026-13",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_trends_default_window(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/trends",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    # Default 30-day window → 30 zero-stress points.
    assert len(resp.json()["points"]) == 30


@pytest.mark.asyncio
async def test_phase_averages_with_explicit_range(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/phase-averages?frm=2026-05-01&to=2026-05-31",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["phases"] == []  # no events for this user


@pytest.mark.asyncio
async def test_heatmap_returns_empty_for_new_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/heatmap?frm=2026-05-01&to=2026-05-31",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["rows"] == []


@pytest.mark.asyncio
async def test_patterns_returns_empty_for_new_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/patterns",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["patterns"] == []


@pytest.mark.asyncio
async def test_inverted_range_returns_422(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/insights/trends?frm=2026-05-31&to=2026-05-01",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422
```

```bash
poetry run pytest app/tests/test_insights_router.py -v
```

Expected: FAIL.

- [ ] **Step 3: Implement router**

`backend/app/insights/router.py`:

```python
"""GET /api/v1/insights/{calendar,trends,phase-averages,heatmap,patterns}."""

from __future__ import annotations

import re
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.insights import (
    InsightsCalendarResponse,
    InsightsHeatmapResponse,
    InsightsPatternsResponse,
    InsightsPhaseAveragesResponse,
    InsightsTrendsResponse,
)
from app.services.insights.calendar import compute_calendar
from app.services.insights.heatmap import compute_heatmap
from app.services.insights.patterns import compute_patterns
from app.services.insights.phase_averages import compute_phase_averages
from app.services.insights.trends import compute_trends

router = APIRouter(prefix="/insights", tags=["insights"])

_MONTH_RE = re.compile(r"^\d{4}-(0[1-9]|1[0-2])$")
_DEFAULT_WINDOW = timedelta(days=30)


def _default_range() -> tuple[date, date]:
    today = datetime.now(tz=UTC).date()
    return today - _DEFAULT_WINDOW, today


def _validate_range(frm: date | None, to: date | None) -> tuple[date, date]:
    default_frm, default_to = _default_range()
    f = frm or default_frm
    t = to or default_to
    if f > t:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "frm_must_be_le_to"},
        )
    return f, t


@router.get("/calendar", response_model=InsightsCalendarResponse)
async def calendar(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    month: Annotated[str, Query()],
) -> InsightsCalendarResponse:
    if not _MONTH_RE.match(month):
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "invalid_month"},
        )
    return await compute_calendar(db, user_id=user.id, month=month)


@router.get("/trends", response_model=InsightsTrendsResponse)
async def trends(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsTrendsResponse:
    f, t = _validate_range(frm, to)
    return await compute_trends(db, user_id=user.id, frm=f, to=t)


@router.get("/phase-averages", response_model=InsightsPhaseAveragesResponse)
async def phase_averages(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsPhaseAveragesResponse:
    f, t = _validate_range(frm, to)
    return await compute_phase_averages(db, user_id=user.id, frm=f, to=t)


@router.get("/heatmap", response_model=InsightsHeatmapResponse)
async def heatmap(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsHeatmapResponse:
    f, t = _validate_range(frm, to)
    return await compute_heatmap(db, user_id=user.id, frm=f, to=t)


@router.get("/patterns", response_model=InsightsPatternsResponse)
async def patterns(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> InsightsPatternsResponse:
    f, t = _validate_range(frm, to)
    return await compute_patterns(db, user_id=user.id, frm=f, to=t)
```

- [ ] **Step 4: Wire main.py**

`from app.insights.router import router as insights_router` and `app.include_router(insights_router, prefix="/api/v1")`.

- [ ] **Step 5: Run tests**

```bash
poetry run pytest app/tests/test_insights_router.py -v
```

Expected: 7 PASS.

- [ ] **Step 6: Commit**

```bash
git add app/insights app/main.py app/tests/test_insights_router.py
git commit -m "feat(insights): GET /api/v1/insights/* (5 endpoints)"
```

---

## Task 8: Final verification

- [ ] **Step 1: Migrate test DB + run full suite + lint + types**

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
make migrate-test
poetry run pytest
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
```

- [ ] **Step 2: OpenAPI smoke**

```bash
poetry run python -c "
from app.main import app
schema = app.openapi()
paths = schema['paths']
for p in (
    '/api/v1/insights/calendar',
    '/api/v1/insights/trends',
    '/api/v1/insights/phase-averages',
    '/api/v1/insights/heatmap',
    '/api/v1/insights/patterns',
):
    assert p in paths, f'missing {p}'
for s in ('InsightsCalendarResponse','InsightsTrendsResponse','InsightsPhaseAveragesResponse','InsightsHeatmapResponse','InsightsPatternsResponse'):
    assert s in schema['components']['schemas'], f'missing {s}'
print('ok')
"
```

- [ ] **Step 3: Format-only commit if needed**

```bash
git add -A
git diff --cached --quiet && echo "nothing" || git commit -m "chore: ruff format"
```

---

## Done-when

- All 5 insights endpoints respond 200 for new users with empty payloads, return real aggregates for populated users.
- Calendar covers a full month grid including phase classification per day.
- Trends/Phase-averages/Heatmap/Patterns all use a default 30-day window when no range is given.
- Patterns excludes combinations with <3 events or <15% delta from baseline.
- Per-user isolation verified end-to-end.
- ~7 commits.
