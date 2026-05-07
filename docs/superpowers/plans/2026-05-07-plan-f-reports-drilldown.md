# Plan F — Reports Drill-down Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Power the My-Report drill-down screens (Work × Luteal, Physical × Menstrual, etc.) with one endpoint that returns count, avg stress, top mood, most-common day-of-phase, a per-cycle-day heatmap of intensity, and a recent-events list.

**Architecture:** Single GET endpoint `/api/v1/reports/drilldown` taking `category_id`, `phase`, and a date window. Backed by a service that composes a single SQL pass + the Plan E `cycle_lookup` classifier. No new tables. Reuses Plan E's per-event phase classifier so the math is identical to what Insights shows on the parent screen.

**Tech Stack:** Python 3.12, FastAPI 0.136, SQLAlchemy 2.0 async, Pydantic v2.

---

## Decisions Locked

- One endpoint: `GET /api/v1/reports/drilldown`. Required query params: `phase`. Optional: `category_id` (omit = uncategorized; pass UUID = that category), `frm`, `to`.
- `category_id=null` is encoded as the literal absence of the parameter — the FE sends `?phase=luteal` for "Uncategorized × Luteal".
- Phase day numbers are 1-indexed within the cycle (matching `compute_phase`):
  - menstrual: days 1-5 (5 cells)
  - follicular: days 6-13 (8 cells)
  - ovulation: days 14-16 (3 cells)
  - luteal: days 17 .. cycle_length (typically 12 cells)
- For luteal, the heatmap returns cells from 17 through `max(cycle_length_days, max(observed_day))`. Per-event cycle_length is read from the cycle that was active at the time of that event (so a user who switched from 28- to 30-day cycles mid-window still gets a coherent grid). Default to 28 when missing.
- "Most common day" = the day-of-phase with the highest event count. Tie → the earliest day.
- "Top mood" = first chip from the most frequently-occurring `mood_chips[0]` in the bucket. Empty mood arrays are ignored.
- "Recent events" = up to 10 events ordered by `detected_at DESC`, with their cycle day attached.
- Date window default = latest 90 days (drill-downs typically want a longer view than the Insights default 30).

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `backend/app/schemas/reports.py` | **Create** | DrilldownRequest filter + DrilldownResponse + nested DTOs |
| `backend/app/services/reports/__init__.py` | **Create** | Package marker |
| `backend/app/services/reports/drilldown.py` | **Create** | Pure async service: filter events, compute summary, heatmap, recent list |
| `backend/app/reports/__init__.py` | **Create** | Package marker |
| `backend/app/reports/router.py` | **Create** | `GET /api/v1/reports/drilldown` |
| `backend/app/main.py` | **Modify** | Wire the router |
| `backend/app/tests/test_reports_drilldown_service.py` | **Create** | Unit tests on the service |
| `backend/app/tests/test_reports_drilldown_router.py` | **Create** | End-to-end tests |

---

## Task 1: Schemas

**Files:**
- Create: `backend/app/schemas/reports.py`

- [ ] **Step 1: Failing schema test**

`backend/app/tests/test_reports_schemas.py`:

```python
from __future__ import annotations

from datetime import UTC, date, datetime


def test_drilldown_response_serialises() -> None:
    from app.schemas.reports import (
        DrilldownEvent,
        DrilldownHeatmapDay,
        DrilldownResponse,
        DrilldownSummary,
    )

    body = DrilldownResponse.model_validate({
        "summary": {
            "category_id": None,
            "category_name": "Uncategorized",
            "phase": "luteal",
            "event_count": 12,
            "avg_stress": 74.0,
            "top_mood": "anxious",
            "most_common_day": 20,
            "frm": date(2026, 5, 1).isoformat(),
            "to": date(2026, 9, 30).isoformat(),
        },
        "heatmap": [
            {"day": 17, "event_count": 1, "avg_stress": 60.0},
            {"day": 18, "event_count": 0, "avg_stress": None},
        ],
        "recent_events": [
            {
                "id": "00000000-0000-0000-0000-000000000001",
                "detected_at": datetime(2026, 9, 20, 14, 48, tzinfo=UTC).isoformat(),
                "cycle_day": 20,
                "user_stress_level": 78,
                "top_mood": "anxious",
                "log_text": "Client meeting went long",
            }
        ],
    })
    assert isinstance(body.summary, DrilldownSummary)
    assert isinstance(body.heatmap[0], DrilldownHeatmapDay)
    assert isinstance(body.recent_events[0], DrilldownEvent)
```

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
poetry run pytest app/tests/test_reports_schemas.py -v
```

Expected: FAIL.

- [ ] **Step 2: Create schemas**

`backend/app/schemas/reports.py`:

```python
"""Wire schemas for /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class DrilldownSummary(BaseModel):
    category_id: uuid.UUID | None
    category_name: str
    phase: str  # menstrual / follicular / ovulation / luteal
    event_count: int
    avg_stress: float | None
    top_mood: str | None
    most_common_day: int | None
    frm: date
    to: date


class DrilldownHeatmapDay(BaseModel):
    day: int  # cycle day, 1-indexed
    event_count: int
    avg_stress: float | None


class DrilldownEvent(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    detected_at: datetime
    cycle_day: int | None
    user_stress_level: int | None
    top_mood: str | None
    log_text: str | None


class DrilldownResponse(BaseModel):
    summary: DrilldownSummary
    heatmap: list[DrilldownHeatmapDay]
    recent_events: list[DrilldownEvent]
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_reports_schemas.py -v
poetry run mypy app/schemas/reports.py
git add app/schemas/reports.py app/tests/test_reports_schemas.py
git commit -m "feat(schemas): drill-down report DTOs"
```

---

## Task 2: Drill-down service

**Files:**
- Create: `backend/app/services/reports/__init__.py`
- Create: `backend/app/services/reports/drilldown.py`
- Create: `backend/app/tests/test_reports_drilldown_service.py`

- [ ] **Step 1: Empty package marker**

```bash
mkdir -p backend/app/services/reports
touch backend/app/services/reports/__init__.py
```

- [ ] **Step 2: Failing tests**

`backend/app/tests/test_reports_drilldown_service.py`:

```python
"""Service-level tests for compute_drilldown."""

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
async def test_drilldown_for_empty_user_returns_zero_summary(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,
        phase="luteal",
        frm=date(2026, 5, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 0
    assert body.summary.avg_stress is None
    assert body.summary.top_mood is None
    assert body.summary.most_common_day is None
    # Heatmap still shows the canonical day grid for the phase, with zeros.
    assert {d.day for d in body.heatmap} == {17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28}
    assert all(d.event_count == 0 and d.avg_stress is None for d in body.heatmap)
    assert body.recent_events == []


@pytest.mark.asyncio
async def test_drilldown_aggregates_for_category_phase(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 9, 1),  # so day 19 = Sept 19, day 20 = Sept 20
        cycle_length_days=28,
    ))
    work = TriggerCategory(
        id=uuid.uuid4(), user_id=me.id, name="Work", color="#7C3AED", sort_order=0,
    )
    db_session.add(work)

    # 3 events on cycle day 20 — should be most_common_day.
    for level in (70, 78, 75):
        db_session.add(StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 9, 20, 14, tzinfo=UTC),
            logged=True,
            user_stress_level=level,
            mood_chips=["anxious"],
            category_id=work.id,
        ))
    # 2 events on day 19.
    for level in (60, 65):
        db_session.add(StressEvent(
            id=uuid.uuid4(),
            user_id=me.id,
            detected_at=datetime(2026, 9, 19, 9, tzinfo=UTC),
            logged=True,
            user_stress_level=level,
            mood_chips=["overwhelmed"],
            category_id=work.id,
        ))
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=work.id,
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 5
    assert body.summary.avg_stress == round((70 + 78 + 75 + 60 + 65) / 5, 2)
    assert body.summary.top_mood == "anxious"  # 3 vs 2
    assert body.summary.most_common_day == 20

    by_day = {d.day: d for d in body.heatmap}
    assert by_day[20].event_count == 3
    assert by_day[20].avg_stress == round((70 + 78 + 75) / 3, 2)
    assert by_day[19].event_count == 2
    assert by_day[17].event_count == 0  # untouched cells appear with zero

    assert len(body.recent_events) == 5  # all five fit under the 10-cap
    # Newest first.
    assert body.recent_events[0].cycle_day == 20


@pytest.mark.asyncio
async def test_drilldown_filters_by_uncategorized_when_category_id_none(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 9, 1),
        cycle_length_days=28,
    ))
    work = TriggerCategory(
        id=uuid.uuid4(), user_id=me.id, name="Work", color="#7C3AED", sort_order=0,
    )
    db_session.add(work)

    # categorized
    db_session.add(StressEvent(
        id=uuid.uuid4(), user_id=me.id,
        detected_at=datetime(2026, 9, 20, tzinfo=UTC),
        logged=True, user_stress_level=80, category_id=work.id,
    ))
    # uncategorized
    db_session.add(StressEvent(
        id=uuid.uuid4(), user_id=me.id,
        detected_at=datetime(2026, 9, 21, tzinfo=UTC),
        logged=True, user_stress_level=40,
    ))
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,  # filter for uncategorized only
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert body.summary.event_count == 1
    assert body.summary.category_name == "Uncategorized"
    assert body.summary.avg_stress == 40.0


@pytest.mark.asyncio
async def test_drilldown_caps_recent_events_at_10(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.reports.drilldown import compute_drilldown

    me = await make_user()
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=date(2026, 9, 1),
        cycle_length_days=28,
    ))
    for hour in range(15):
        db_session.add(StressEvent(
            id=uuid.uuid4(), user_id=me.id,
            detected_at=datetime(2026, 9, 20, hour, tzinfo=UTC),
            logged=True, user_stress_level=50,
        ))
    await db_session.flush()

    body = await compute_drilldown(
        db_session,
        user_id=me.id,
        category_id=None,
        phase="luteal",
        frm=date(2026, 9, 1),
        to=date(2026, 9, 30),
    )
    assert len(body.recent_events) == 10
```

```bash
poetry run pytest app/tests/test_reports_drilldown_service.py -v
```

Expected: FAIL.

- [ ] **Step 3: Implement service**

`backend/app/services/reports/drilldown.py`:

```python
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
    levels = [
        float(ev.user_stress_level) for ev, _ in matched
        if ev.user_stress_level is not None
    ]
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
        sorted(day_counts.items(), key=lambda kv: (-kv[1], kv[0]))[0][0]
        if day_counts
        else None
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
        recent.append(DrilldownEvent(
            id=ev.id,
            detected_at=ev.detected_at,
            cycle_day=day,
            user_stress_level=ev.user_stress_level,
            top_mood=(ev.mood_chips[0] if ev.mood_chips else None),
            log_text=ev.log_text,
        ))

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
```

- [ ] **Step 4: Tests pass + commit**

```bash
poetry run pytest app/tests/test_reports_drilldown_service.py -v
poetry run mypy app/services/reports/drilldown.py
git add app/services/reports app/tests/test_reports_drilldown_service.py
git commit -m "feat(reports): drill-down service (summary + heatmap + recent events)"
```

---

## Task 3: Router

**Files:**
- Create: `backend/app/reports/__init__.py`
- Create: `backend/app/reports/router.py`
- Modify: `backend/app/main.py`
- Create: `backend/app/tests/test_reports_drilldown_router.py`

- [ ] **Step 1: Empty package**

```bash
mkdir -p backend/app/reports
touch backend/app/reports/__init__.py
```

- [ ] **Step 2: Failing router test**

`backend/app/tests/test_reports_drilldown_router.py`:

```python
"""End-to-end tests for /api/v1/reports/drilldown."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_drilldown_smokes_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=luteal&frm=2026-09-01&to=2026-09-30",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["summary"]["event_count"] == 0
    assert body["summary"]["category_name"] == "Uncategorized"
    assert len(body["heatmap"]) == 12  # luteal default 17..28 inclusive
    assert body["recent_events"] == []


@pytest.mark.asyncio
async def test_drilldown_rejects_unknown_phase(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=weekend",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_drilldown_default_window_when_omitted(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=menstrual",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    # menstrual is days 1-5
    body = resp.json()
    assert {d["day"] for d in body["heatmap"]} == {1, 2, 3, 4, 5}


@pytest.mark.asyncio
async def test_drilldown_rejects_inverted_range(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/reports/drilldown?phase=luteal&frm=2026-09-30&to=2026-09-01",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_drilldown_other_user_category_is_ignored(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()

    cat = (
        await client.post(
            "/api/v1/categories",
            headers=auth_headers(str(other.supabase_user_id)),
            json={"name": "Theirs", "color": "#111111"},
        )
    ).json()

    resp = await client.get(
        f"/api/v1/reports/drilldown?phase=luteal&category_id={cat['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    # Foreign category resolves to "Unknown" with 0 events; we don't 404 to keep
    # the FE error model simple, but no events of the calling user belong to it.
    assert resp.status_code == 200
    assert resp.json()["summary"]["event_count"] == 0
```

```bash
poetry run pytest app/tests/test_reports_drilldown_router.py -v
```

Expected: FAIL.

- [ ] **Step 3: Implement router**

`backend/app/reports/router.py`:

```python
"""GET /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.reports import DrilldownResponse
from app.services.reports.drilldown import compute_drilldown

router = APIRouter(prefix="/reports", tags=["reports"])

_DEFAULT_WINDOW = timedelta(days=90)
_VALID_PHASES = {"menstrual", "follicular", "ovulation", "luteal"}


@router.get(
    "/drilldown",
    response_model=DrilldownResponse,
    summary="Per (category, phase) report — summary, heatmap, recent events",
)
async def drilldown(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    phase: Annotated[str, Query()],
    category_id: Annotated[uuid.UUID | None, Query()] = None,
    frm: Annotated[date | None, Query()] = None,
    to: Annotated[date | None, Query()] = None,
) -> DrilldownResponse:
    if phase not in _VALID_PHASES:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "unsupported_phase"},
        )
    today = datetime.now(tz=UTC).date()
    f = frm or today - _DEFAULT_WINDOW
    t = to or today
    if f > t:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "frm_must_be_le_to"},
        )
    return await compute_drilldown(
        db,
        user_id=user.id,
        category_id=category_id,
        phase=phase,
        frm=f,
        to=t,
    )
```

- [ ] **Step 4: Wire main**

Add `from app.reports.router import router as reports_router` and `app.include_router(reports_router, prefix="/api/v1")`.

- [ ] **Step 5: Run tests**

```bash
poetry run pytest app/tests/test_reports_drilldown_router.py -v
```

Expected: 5 PASS.

- [ ] **Step 6: Commit**

```bash
git add app/reports app/main.py app/tests/test_reports_drilldown_router.py
git commit -m "feat(reports): GET /api/v1/reports/drilldown"
```

---

## Task 4: Final verification

- [ ] **Step 1: Migrate test DB + full suite + lint + types**

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
assert '/api/v1/reports/drilldown' in schema['paths']
for s in ('DrilldownResponse','DrilldownSummary','DrilldownHeatmapDay','DrilldownEvent'):
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

- `GET /api/v1/reports/drilldown?phase=luteal&category_id=<uuid>` returns summary + heatmap + recent_events for an existing bucket.
- Empty buckets return zero summary, zero-filled heatmap, and `recent_events: []`.
- Heatmap day count matches the phase: 5 (menstrual), 8 (follicular), 3 (ovulation), 12+ (luteal, depending on cycle length).
- Recent events capped at 10 with cycle_day attached.
- Other users' category IDs resolve to "Unknown" with zero events (no leak).
- ~3 commits.
