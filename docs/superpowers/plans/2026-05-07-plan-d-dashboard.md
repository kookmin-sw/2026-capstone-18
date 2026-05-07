# Plan D — Dashboard Aggregate Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Render the Home screen in one HTTP request — `GET /api/v1/dashboard/today` returns the user's latest stress level, last night's sleep, latest mood, today's event count, and current cycle phase + days-left in one shot.

**Architecture:** A read-only service composing four async queries (stress events, sleep logs, mood, cycle) with the existing `compute_phase` helper. No new DB tables — depends on Plans A (`user_stress_level`, `mood_chips`), B (`category_id` for the event count breakdown), and C (`sleep_logs`). Failure mode for new users with no data: every field is null, but the endpoint still 200s — the client renders the empty-state screen on its own.

**Tech Stack:** Python 3.12, FastAPI 0.136, SQLAlchemy 2.0 async, Pydantic v2.

---

## Decisions Locked

- One endpoint, `GET /api/v1/dashboard/today`. No body, no params (the user's "today" is **server-side UTC** for v1; Plan G can add a `?tz=` parameter when we wire a real timezone column on the user).
- **Stress level**: shows `user_stress_level` from the most recent **logged** event in the last 24h. If none, falls back to the most recent `model_confidence` * 100 from the last 24h. If neither, returns `null`.
- **Sleep**: latest `sleep_logs` row by `ended_on`. The card needs `total_minutes` and `rating`.
- **Emotion / mood**: most recent non-empty `mood_chips[0]` from a logged event in the last 24h. The Figma copy uses a single mood word ("Anxious"), so we surface the first chip.
- **Events count**: number of stress events with `detected_at` in the last 24h.
- **Cycle**: `phase`, `day`, `days_left_in_phase`, plus `cycle_length_days` echoed back so the client can render the phase progress bar without a second call. Computed via `compute_phase` against the latest `cycles` row. Returns `null` for users with no recorded period.
- 24h window is `now() - interval '24 hours'` rather than "calendar day" — DST-and-tz-resilient and matches the user's intuition of "today" when they open the app at 9am.

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `backend/app/schemas/dashboard.py` | **Create** | `DashboardTodayResponse` + nested DTOs |
| `backend/app/services/dashboard.py` | **Create** | Pure async aggregator: takes session+user, returns a Pydantic response |
| `backend/app/services/cycle_phase.py` | **Modify** | Add `phase_window(phase, day, cycle_length)` helper returning `days_left` |
| `backend/app/dashboard/__init__.py` | **Create** | Package marker |
| `backend/app/dashboard/router.py` | **Create** | `GET /api/v1/dashboard/today` |
| `backend/app/main.py` | **Modify** | Wire the router |
| `backend/app/tests/test_cycle_phase_window.py` | **Create** | Pure-function unit tests for `phase_window` |
| `backend/app/tests/test_dashboard_router.py` | **Create** | End-to-end coverage of populated and empty states |

---

## Task 1: `phase_window` helper

The home screen needs "9 days left" — `compute_phase` returns only `(phase, day)`. Add a sibling helper that computes how many days remain in the current phase (or until next period for luteal).

**Files:**
- Modify: `backend/app/services/cycle_phase.py`
- Create: `backend/app/tests/test_cycle_phase_window.py`

- [ ] **Step 1: Failing unit test**

`backend/app/tests/test_cycle_phase_window.py`:

```python
"""Unit tests for the phase_window helper."""

from __future__ import annotations

import pytest


def test_phase_window_menstrual_day_1() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="menstrual", day=1, cycle_length_days=28) == 5


def test_phase_window_menstrual_last_day() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="menstrual", day=5, cycle_length_days=28) == 1


def test_phase_window_follicular_first_day() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="follicular", day=6, cycle_length_days=28) == 8


def test_phase_window_ovulation_middle() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="ovulation", day=15, cycle_length_days=28) == 2


def test_phase_window_luteal_uses_cycle_length() -> None:
    from app.services.cycle_phase import phase_window
    # Day 19 of a 28-day cycle: 28 - 19 + 1 = 10 days left
    assert phase_window(phase="luteal", day=19, cycle_length_days=28) == 10


def test_phase_window_luteal_long_cycle() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="luteal", day=20, cycle_length_days=35) == 16


def test_phase_window_luteal_overdue_returns_zero() -> None:
    """If the user is past day cycle_length_days, phase_window must not go negative."""
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="luteal", day=30, cycle_length_days=28) == 0


def test_phase_window_pre_period_returns_none() -> None:
    from app.services.cycle_phase import phase_window
    assert phase_window(phase="pre_period", day=0, cycle_length_days=28) is None


def test_phase_window_unknown_phase_raises() -> None:
    from app.services.cycle_phase import phase_window
    with pytest.raises(ValueError):
        phase_window(phase="weekend", day=1, cycle_length_days=28)
```

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
poetry run pytest app/tests/test_cycle_phase_window.py -v
```

Expected: FAIL — `phase_window` doesn't exist.

- [ ] **Step 2: Implement helper**

Append to `backend/app/services/cycle_phase.py`:

```python
def phase_window(*, phase: str, day: int, cycle_length_days: int) -> int | None:
    """Return how many days remain in the current phase (1-indexed, inclusive of today).

    For `luteal`, "remaining" is days until next expected period start. Past the
    expected period, returns 0 (don't lie about a negative future).

    For `pre_period`, returns None — the caller should hide the "X days left" badge.
    Raises ValueError on unknown phase strings.
    """
    if phase == "menstrual":
        return max(0, 5 - day + 1)
    if phase == "follicular":
        return max(0, 13 - day + 1)
    if phase == "ovulation":
        return max(0, 16 - day + 1)
    if phase == "luteal":
        return max(0, cycle_length_days - day + 1)
    if phase == "pre_period":
        return None
    raise ValueError(f"unknown phase: {phase!r}")
```

- [ ] **Step 3: Tests pass**

```bash
poetry run pytest app/tests/test_cycle_phase_window.py -v
```

Expected: all 9 PASS.

- [ ] **Step 4: mypy + commit**

```bash
poetry run mypy app/services/cycle_phase.py
git add app/services/cycle_phase.py app/tests/test_cycle_phase_window.py
git commit -m "feat(cycle): add phase_window helper for days-remaining calculation"
```

---

## Task 2: Response schemas

**Files:**
- Create: `backend/app/schemas/dashboard.py`

- [ ] **Step 1: Failing schema smoke test**

`backend/app/tests/test_dashboard_schema.py`:

```python
from __future__ import annotations


def test_response_classes_exist() -> None:
    from app.schemas.dashboard import (
        DashboardCycle,
        DashboardSleep,
        DashboardStress,
        DashboardTodayResponse,
    )

    assert all(hasattr(cls, "model_fields") for cls in (
        DashboardCycle, DashboardSleep, DashboardStress, DashboardTodayResponse
    ))


def test_response_serialises_with_all_nulls() -> None:
    from app.schemas.dashboard import DashboardTodayResponse

    body = DashboardTodayResponse.model_validate({
        "stress": None,
        "sleep": None,
        "mood": None,
        "events_count_24h": 0,
        "cycle": None,
    })
    dumped = body.model_dump()
    assert dumped["stress"] is None
    assert dumped["events_count_24h"] == 0
```

```bash
poetry run pytest app/tests/test_dashboard_schema.py -v
```

Expected: FAIL.

- [ ] **Step 2: Create schemas**

`backend/app/schemas/dashboard.py`:

```python
"""Wire schemas for /api/v1/dashboard/today."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class DashboardStress(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    level: int  # 0-100, the value the home card shows
    source: str  # "user" if user_stress_level, "model" if derived from model_confidence
    detected_at: datetime
    logged: bool


class DashboardSleep(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    total_minutes: int
    rating: str
    ended_on: date


class DashboardCycle(BaseModel):
    phase: str
    day: int
    days_left_in_phase: int | None
    cycle_length_days: int
    period_start_date: date


class DashboardTodayResponse(BaseModel):
    stress: DashboardStress | None
    sleep: DashboardSleep | None
    mood: str | None
    events_count_24h: int
    cycle: DashboardCycle | None
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_dashboard_schema.py -v
poetry run mypy app/schemas/dashboard.py
git add app/schemas/dashboard.py app/tests/test_dashboard_schema.py
git commit -m "feat(schemas): DashboardTodayResponse"
```

---

## Task 3: Aggregator service

**Files:**
- Create: `backend/app/services/dashboard.py`
- Create: `backend/app/tests/test_dashboard_service.py`

- [ ] **Step 1: Failing tests for the service**

`backend/app/tests/test_dashboard_service.py`:

```python
"""Unit tests for the dashboard aggregator service.

Service-level tests (not router-level) so we can probe each branch in isolation.
"""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_aggregate_returns_all_nulls_for_new_user(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is None
    assert body.sleep is None
    assert body.mood is None
    assert body.events_count_24h == 0
    assert body.cycle is None


@pytest.mark.asyncio
async def test_aggregate_picks_user_stress_level_over_model(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)

    # Older logged event with user_stress_level=70.
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=4),
        logged=True,
        user_stress_level=70,
    ))
    # Newer model-only event (no user value, has confidence).
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=1),
        logged=False,
        model_confidence=0.9,
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is not None
    # Should prefer the *latest logged with user_stress_level* over a more recent
    # model-only event, because the home card represents how the user feels.
    assert body.stress.level == 70
    assert body.stress.source == "user"
    assert body.stress.logged is True


@pytest.mark.asyncio
async def test_aggregate_falls_back_to_model_confidence(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=2),
        logged=False,
        model_confidence=0.62,
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is not None
    assert body.stress.level == 62  # 0.62 * 100
    assert body.stress.source == "model"


@pytest.mark.asyncio
async def test_aggregate_ignores_events_older_than_24h(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=30),
        logged=True,
        user_stress_level=99,
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.stress is None
    assert body.events_count_24h == 0


@pytest.mark.asyncio
async def test_aggregate_returns_latest_sleep_log(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    db_session.add(SleepLog(
        id=uuid.uuid4(),
        user_id=me.id,
        fell_asleep_at=datetime(2026, 5, 6, 23, tzinfo=UTC),
        woke_up_at=datetime(2026, 5, 7, 6, 30, tzinfo=UTC),
        ended_on=date(2026, 5, 7),
        rating="okay",
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.sleep is not None
    assert body.sleep.rating == "okay"
    assert body.sleep.ended_on == date(2026, 5, 7)
    assert body.sleep.total_minutes == 7 * 60 + 30


@pytest.mark.asyncio
async def test_aggregate_extracts_first_mood_chip(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    now = datetime.now(tz=UTC)
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=3),
        logged=True,
        mood_chips=["anxious", "overwhelmed"],
        user_stress_level=55,
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.mood == "anxious"


@pytest.mark.asyncio
async def test_aggregate_computes_cycle_phase_and_days_left(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.dashboard import compute_dashboard_today

    me = await make_user()
    today = datetime.now(tz=UTC).date()
    period_start = today - timedelta(days=18)  # ~ luteal day 19
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=period_start,
        cycle_length_days=28,
    ))
    await db_session.flush()

    body = await compute_dashboard_today(db_session, user_id=me.id)
    assert body.cycle is not None
    assert body.cycle.phase == "luteal"
    assert body.cycle.day == 19
    # 28 - 19 + 1 = 10
    assert body.cycle.days_left_in_phase == 10
    assert body.cycle.cycle_length_days == 28
```

```bash
poetry run pytest app/tests/test_dashboard_service.py -v
```

Expected: FAIL — service doesn't exist.

- [ ] **Step 2: Implement the service**

`backend/app/services/dashboard.py`:

```python
"""Aggregator for /api/v1/dashboard/today.

Composes four independent queries into the single dashboard payload. Returns a
Pydantic model so the router can pass it straight back to FastAPI without
re-validating.
"""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent
from app.schemas.dashboard import (
    DashboardCycle,
    DashboardSleep,
    DashboardStress,
    DashboardTodayResponse,
)
from app.services.cycle_phase import compute_phase, phase_window

WINDOW = timedelta(hours=24)


async def compute_dashboard_today(
    db: AsyncSession,
    *,
    user_id: uuid.UUID,
) -> DashboardTodayResponse:
    cutoff = datetime.now(tz=UTC) - WINDOW

    stress = await _stress(db, user_id=user_id, cutoff=cutoff)
    sleep = await _sleep(db, user_id=user_id)
    mood = await _mood(db, user_id=user_id, cutoff=cutoff)
    events_count = await _events_count(db, user_id=user_id, cutoff=cutoff)
    cycle = await _cycle(db, user_id=user_id)

    return DashboardTodayResponse(
        stress=stress,
        sleep=sleep,
        mood=mood,
        events_count_24h=events_count,
        cycle=cycle,
    )


async def _stress(
    db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime
) -> DashboardStress | None:
    # Prefer the most recent logged event with a user-rated value.
    user_rated = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.user_stress_level.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if user_rated is not None and user_rated.user_stress_level is not None:
        return DashboardStress(
            level=int(user_rated.user_stress_level),
            source="user",
            detected_at=user_rated.detected_at,
            logged=user_rated.logged,
        )

    # Fall back to model confidence on the most recent event.
    model_only = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.model_confidence.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if model_only is not None and model_only.model_confidence is not None:
        return DashboardStress(
            level=int(round(model_only.model_confidence * 100)),
            source="model",
            detected_at=model_only.detected_at,
            logged=model_only.logged,
        )

    return None


async def _sleep(db: AsyncSession, *, user_id: uuid.UUID) -> DashboardSleep | None:
    row = (
        await db.execute(
            select(SleepLog)
            .where(SleepLog.user_id == user_id)
            .order_by(SleepLog.ended_on.desc(), SleepLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    return DashboardSleep(
        total_minutes=row.total_minutes,
        rating=row.rating,
        ended_on=row.ended_on,
    )


async def _mood(
    db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime
) -> str | None:
    row = (
        await db.execute(
            select(StressEvent)
            .where(
                StressEvent.user_id == user_id,
                StressEvent.detected_at >= cutoff,
                StressEvent.logged.is_(True),
                StressEvent.mood_chips.is_not(None),
            )
            .order_by(StressEvent.detected_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None or not row.mood_chips:
        return None
    return row.mood_chips[0]


async def _events_count(
    db: AsyncSession, *, user_id: uuid.UUID, cutoff: datetime
) -> int:
    return int(
        (
            await db.execute(
                select(func.count(StressEvent.id)).where(
                    StressEvent.user_id == user_id,
                    StressEvent.detected_at >= cutoff,
                )
            )
        ).scalar_one()
    )


async def _cycle(db: AsyncSession, *, user_id: uuid.UUID) -> DashboardCycle | None:
    row = (
        await db.execute(
            select(Cycle)
            .where(Cycle.user_id == user_id)
            .order_by(Cycle.period_start_date.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return None
    cycle_length = row.cycle_length_days or 28
    today = datetime.now(tz=UTC).date()
    phase, day = compute_phase(
        today=today,
        period_start_date=row.period_start_date,
        cycle_length_days=cycle_length,
    )
    days_left = phase_window(phase=phase, day=day, cycle_length_days=cycle_length)
    return DashboardCycle(
        phase=phase,
        day=day,
        days_left_in_phase=days_left,
        cycle_length_days=cycle_length,
        period_start_date=row.period_start_date,
    )
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_dashboard_service.py -v
poetry run mypy app/services/dashboard.py
git add app/services/dashboard.py app/tests/test_dashboard_service.py
git commit -m "feat(dashboard): aggregator service composing stress/sleep/mood/cycle"
```

Expected: all 7 service tests PASS.

---

## Task 4: Router

**Files:**
- Create: `backend/app/dashboard/__init__.py`
- Create: `backend/app/dashboard/router.py`
- Modify: `backend/app/main.py`
- Create: `backend/app/tests/test_dashboard_router.py`

- [ ] **Step 1: Empty package marker**

```bash
mkdir -p backend/app/dashboard
touch backend/app/dashboard/__init__.py
```

- [ ] **Step 2: Failing router-level test**

`backend/app/tests/test_dashboard_router.py`:

```python
"""Smoke tests for GET /api/v1/dashboard/today."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.cycle import Cycle
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent


@pytest.mark.asyncio
async def test_get_dashboard_for_empty_user(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    body = resp.json()
    assert body == {
        "stress": None,
        "sleep": None,
        "mood": None,
        "events_count_24h": 0,
        "cycle": None,
    }


@pytest.mark.asyncio
async def test_get_dashboard_with_full_state(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    now = datetime.now(tz=UTC)
    today = now.date()

    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=me.id,
        detected_at=now - timedelta(hours=2),
        logged=True,
        user_stress_level=62,
        mood_chips=["anxious"],
    ))
    db_session.add(SleepLog(
        id=uuid.uuid4(),
        user_id=me.id,
        fell_asleep_at=datetime.combine(today - timedelta(days=1),
                                       datetime.min.time(), tzinfo=UTC) + timedelta(hours=23),
        woke_up_at=datetime.combine(today, datetime.min.time(), tzinfo=UTC) + timedelta(hours=6, minutes=48),
        ended_on=today,
        rating="okay",
    ))
    db_session.add(Cycle(
        id=uuid.uuid4(),
        user_id=me.id,
        period_start_date=today - timedelta(days=18),
        cycle_length_days=28,
    ))
    await db_session.flush()

    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["stress"]["level"] == 62
    assert body["stress"]["source"] == "user"
    assert body["sleep"]["rating"] == "okay"
    assert body["sleep"]["total_minutes"] > 0
    assert body["mood"] == "anxious"
    assert body["events_count_24h"] == 1
    assert body["cycle"]["phase"] == "luteal"
    assert body["cycle"]["day"] == 19
    assert body["cycle"]["days_left_in_phase"] == 10
    assert body["cycle"]["cycle_length_days"] == 28


@pytest.mark.asyncio
async def test_get_dashboard_isolated_per_user(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    db_session.add(StressEvent(
        id=uuid.uuid4(),
        user_id=other.id,
        detected_at=datetime.now(tz=UTC) - timedelta(hours=1),
        logged=True,
        user_stress_level=99,
    ))
    await db_session.flush()

    resp = await client.get(
        "/api/v1/dashboard/today",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 200
    assert resp.json()["stress"] is None
```

```bash
poetry run pytest app/tests/test_dashboard_router.py -v
```

Expected: FAIL — router doesn't exist.

- [ ] **Step 3: Implement router**

`backend/app/dashboard/router.py`:

```python
"""GET /api/v1/dashboard/today."""

from __future__ import annotations

from typing import Annotated

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.user import User
from app.schemas.dashboard import DashboardTodayResponse
from app.services.dashboard import compute_dashboard_today

router = APIRouter(prefix="/dashboard", tags=["dashboard"])


@router.get(
    "/today",
    response_model=DashboardTodayResponse,
    summary="Single-shot home screen aggregate",
)
async def get_today(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> DashboardTodayResponse:
    return await compute_dashboard_today(db, user_id=user.id)
```

- [ ] **Step 4: Wire main.py**

Add `from app.dashboard.router import router as dashboard_router` and `app.include_router(dashboard_router, prefix="/api/v1")`.

- [ ] **Step 5: Run tests**

```bash
poetry run pytest app/tests/test_dashboard_router.py -v
```

Expected: 3 PASS.

- [ ] **Step 6: Commit**

```bash
git add app/dashboard app/main.py app/tests/test_dashboard_router.py
git commit -m "feat(dashboard): GET /api/v1/dashboard/today"
```

---

## Task 5: Verification

- [ ] **Step 1: Apply migrations to test DB + full suite**

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
make migrate-test
poetry run pytest
```

Expected: green (modulo Plan A's pre-existing APP_VERSION failures).

- [ ] **Step 2: Lint + types + OpenAPI**

```bash
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
poetry run python -c "
from app.main import app
schema = app.openapi()
assert '/api/v1/dashboard/today' in schema['paths']
props = schema['components']['schemas']['DashboardTodayResponse']['properties']
for f in ('stress','sleep','mood','events_count_24h','cycle'):
    assert f in props, f'{f} missing'
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

- `GET /api/v1/dashboard/today` returns the full payload for a populated user and an all-null payload for a brand-new user.
- Stress card prefers user-rated level over model confidence, falls back when only model is available, and ignores events older than 24h.
- Mood is the first chip of the most recent logged event in the last 24h.
- Cycle includes `days_left_in_phase` derived from the new `phase_window` helper.
- Other users' data never leaks (covered by `test_get_dashboard_isolated_per_user`).
- ~5 commits.
