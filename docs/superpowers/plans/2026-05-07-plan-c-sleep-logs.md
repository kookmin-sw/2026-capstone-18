# Plan C — Sleep Logs CRUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist user-reported sleep windows so the Sleep Log screen, the Home dashboard ("6.8h"), and the Sleep notification flow have a backing endpoint.

**Architecture:** A new per-user `sleep_logs` table keyed by `(user_id, ended_on)` so we can answer "did the user already log last night?" with one indexed lookup. `total_minutes` is a generated column derived from start/end so we never store inconsistent data. Rating is a constrained string enum matching the Figma chips. CRUD endpoints follow the same pattern as `events/router.py` (auth, route ownership, 404-on-foreign).

**Tech Stack:** Python 3.12, FastAPI 0.136, SQLAlchemy 2.0 async, Alembic, Pydantic v2.

---

## Decisions Locked

- Window represented by two timezone-aware timestamps (`fell_asleep_at`, `woke_up_at`). Both required.
- `ended_on DATE NOT NULL` is the **calendar date the user woke up on** (the user's local date, sent by the client). This is the unique key for "last night's sleep" — clients pass the local date so DST and travel don't break the lookup.
- `total_minutes INT` is a Postgres-generated column from `EXTRACT(EPOCH FROM (woke_up_at - fell_asleep_at)) / 60`. Cap-checked on the way in (1–24h).
- `rating` is one of `very_poor / poor / okay / good / great`. Required field — matches the Figma "How did you sleep?" chip group which has no neutral default.
- One log per `(user_id, ended_on)` enforced by a unique index. PUT-style upsert handled by clients re-PATCH'ing the existing row, not by server-side merge.
- No reminders here — sleep nudge scheduling lives in Plan G.

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `backend/alembic/versions/<rev>_add_sleep_logs.py` | **Create** | Table + indexes + generated column |
| `backend/app/models/sleep_log.py` | **Create** | `SleepLog` mapped class |
| `backend/app/schemas/sleep_logs.py` | **Create** | Create / Update / Response / List |
| `backend/app/sleep/__init__.py` | **Create** | Package marker |
| `backend/app/sleep/router.py` | **Create** | POST / GET list / GET latest / GET id / PATCH / DELETE |
| `backend/app/main.py` | **Modify** | `include_router(sleep_router)` |
| `backend/app/tests/test_sleep_logs_router.py` | **Create** | Full CRUD coverage + unique-per-day enforcement |

---

## Task 1: Migration — `sleep_logs` table

**Files:**
- Create: `backend/alembic/versions/<auto>_add_sleep_logs.py`

- [ ] **Step 1: Confirm head and generate scaffold**

```bash
cd backend
poetry run alembic heads
```

Expected: the head set by Plan B's last migration (e.g. `<plan_b_rev> (head)`). If you see Plan A's `6de161daa1f1` instead, Plan B has not been applied to this branch yet — stop and reconcile.

```bash
poetry run alembic revision -m "add sleep logs"
```

- [ ] **Step 2: Write migration**

Replace contents:

```python
"""add sleep logs

Revision ID: <NEW_REVISION>
Revises: <PLAN_B_REVISION>
Create Date: <auto>
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '<NEW_REVISION>'
down_revision: Union[str, Sequence[str], None] = '<PLAN_B_REVISION>'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "sleep_logs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("fell_asleep_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("woke_up_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_on", sa.Date(), nullable=False),
        sa.Column(
            "total_minutes",
            sa.Integer(),
            sa.Computed(
                "(EXTRACT(EPOCH FROM (woke_up_at - fell_asleep_at)) / 60)::int",
                persisted=True,
            ),
            nullable=False,
        ),
        sa.Column("rating", sa.String(length=16), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_sleep_logs_user_id_ended_on",
        "sleep_logs",
        ["user_id", "ended_on"],
    )
    op.create_index(
        "uq_sleep_logs_user_ended",
        "sleep_logs",
        ["user_id", "ended_on"],
        unique=True,
    )
    op.create_check_constraint(
        "ck_sleep_logs_window_positive",
        "sleep_logs",
        sa.text("woke_up_at > fell_asleep_at"),
    )
    op.create_check_constraint(
        "ck_sleep_logs_total_minutes_range",
        "sleep_logs",
        sa.text("total_minutes BETWEEN 60 AND 1440"),
    )
    op.create_check_constraint(
        "ck_sleep_logs_rating_enum",
        "sleep_logs",
        sa.text(
            "rating IN ('very_poor','poor','okay','good','great')"
        ),
    )


def downgrade() -> None:
    op.drop_constraint("ck_sleep_logs_rating_enum", "sleep_logs", type_="check")
    op.drop_constraint("ck_sleep_logs_total_minutes_range", "sleep_logs", type_="check")
    op.drop_constraint("ck_sleep_logs_window_positive", "sleep_logs", type_="check")
    op.drop_index("uq_sleep_logs_user_ended", table_name="sleep_logs")
    op.drop_index("ix_sleep_logs_user_id_ended_on", table_name="sleep_logs")
    op.drop_table("sleep_logs")
```

- [ ] **Step 3: Apply and verify**

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
make migrate
poetry run python -c "
import asyncio, asyncpg, os
async def main():
    dsn = os.environ['DATABASE_URL'].replace('+asyncpg','')
    conn = await asyncpg.connect(dsn)
    assert await conn.fetchval(\"SELECT to_regclass('public.sleep_logs')\") == 'sleep_logs'
    cols = {r['column_name']: r['data_type'] for r in await conn.fetch(
        \"\"\"SELECT column_name, data_type FROM information_schema.columns
              WHERE table_name='sleep_logs'\"\"\"
    )}
    for k in ('id','user_id','fell_asleep_at','woke_up_at','ended_on','total_minutes','rating'):
        assert k in cols, f'{k} missing'
    # Generated column reports as integer with is_generated='ALWAYS'
    gen = await conn.fetchval(\"\"\"SELECT is_generated FROM information_schema.columns
        WHERE table_name='sleep_logs' AND column_name='total_minutes'\"\"\")
    assert gen == 'ALWAYS', f'total_minutes not generated: {gen}'
    print('ok')
    await conn.close()
asyncio.run(main())
"
```

Expected: `ok`.

- [ ] **Step 4: Round-trip downgrade/upgrade**

```bash
poetry run alembic downgrade -1 && poetry run alembic upgrade head
```

- [ ] **Step 5: Commit**

```bash
git add alembic/versions/*_add_sleep_logs.py
git commit -m "feat(db): add sleep_logs table with generated total_minutes"
```

---

## Task 2: SQLAlchemy model

**Files:**
- Create: `backend/app/models/sleep_log.py`

- [ ] **Step 1: Failing smoke test**

`backend/app/tests/test_sleep_log_model.py`:

```python
from __future__ import annotations


def test_sleep_log_attributes() -> None:
    from app.models.sleep_log import SleepLog

    for attr in (
        "id", "user_id", "fell_asleep_at", "woke_up_at", "ended_on",
        "total_minutes", "rating", "note", "created_at",
    ):
        assert hasattr(SleepLog, attr), f"missing {attr}"
```

```bash
cd backend
poetry run pytest app/tests/test_sleep_log_model.py -v
```

Expected: FAIL.

- [ ] **Step 2: Create model**

`backend/app/models/sleep_log.py`:

```python
"""SleepLog — one user-reported sleep window per night."""

from __future__ import annotations

import uuid
from datetime import date, datetime
from typing import TYPE_CHECKING

from sqlalchemy import Computed, Date, DateTime, ForeignKey, Integer, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

if TYPE_CHECKING:
    from app.models.user import User


class SleepLog(Base):
    __tablename__ = "sleep_logs"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    fell_asleep_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    woke_up_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    ended_on: Mapped[date] = mapped_column(Date, nullable=False)
    total_minutes: Mapped[int] = mapped_column(
        Integer,
        Computed("(EXTRACT(EPOCH FROM (woke_up_at - fell_asleep_at)) / 60)::int", persisted=True),
        nullable=False,
    )
    rating: Mapped[str] = mapped_column(String(16), nullable=False)
    note: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=text("now()"),
    )

    user: Mapped["User"] = relationship("User")
```

If `app/models/stress_event.py` uses bare `sa.UUID()` for `id`/`user_id` rather than the `PgUUID` import, match that style.

- [ ] **Step 3: Tests pass**

```bash
poetry run pytest app/tests/test_sleep_log_model.py -v
```

Expected: PASS.

- [ ] **Step 4: mypy + commit**

```bash
poetry run mypy app/models/sleep_log.py
git add app/models/sleep_log.py app/tests/test_sleep_log_model.py
git commit -m "feat(models): add SleepLog mapped class"
```

---

## Task 3: Pydantic schemas

**Files:**
- Create: `backend/app/schemas/sleep_logs.py`

- [ ] **Step 1: Failing schema tests**

Append to `backend/app/tests/test_sleep_log_model.py`:

```python
import pytest
from datetime import UTC, date, datetime
from pydantic import ValidationError


def test_create_validates_window_order() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    fa = datetime(2026, 5, 6, 23, 30, tzinfo=UTC)
    wu = datetime(2026, 5, 7, 7, 15, tzinfo=UTC)

    SleepLogCreate.model_validate({
        "fell_asleep_at": fa.isoformat(),
        "woke_up_at": wu.isoformat(),
        "ended_on": date(2026, 5, 7).isoformat(),
        "rating": "okay",
    })

    # woke_up_at <= fell_asleep_at must reject
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate({
            "fell_asleep_at": wu.isoformat(),
            "woke_up_at": fa.isoformat(),
            "ended_on": date(2026, 5, 7).isoformat(),
            "rating": "okay",
        })


def test_create_validates_rating_enum() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    base = {
        "fell_asleep_at": datetime(2026, 5, 6, 23, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 7, 7, tzinfo=UTC).isoformat(),
        "ended_on": date(2026, 5, 7).isoformat(),
    }
    SleepLogCreate.model_validate({**base, "rating": "great"})
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate({**base, "rating": "amazing"})


def test_create_caps_window_at_24h() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    too_long = {
        "fell_asleep_at": datetime(2026, 5, 6, 1, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 8, 2, tzinfo=UTC).isoformat(),  # 25h
        "ended_on": date(2026, 5, 8).isoformat(),
        "rating": "okay",
    }
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate(too_long)
```

```bash
poetry run pytest app/tests/test_sleep_log_model.py -k "validate" -v
```

Expected: FAIL — schema doesn't exist.

- [ ] **Step 2: Create schemas**

`backend/app/schemas/sleep_logs.py`:

```python
"""Wire schemas for /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

SleepRating = Literal["very_poor", "poor", "okay", "good", "great"]


class SleepLogCreate(BaseModel):
    fell_asleep_at: datetime
    woke_up_at: datetime
    ended_on: date
    rating: SleepRating
    note: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def _validate_window(self) -> "SleepLogCreate":
        if self.woke_up_at <= self.fell_asleep_at:
            raise ValueError("woke_up_at must be after fell_asleep_at")
        delta = self.woke_up_at - self.fell_asleep_at
        if delta < timedelta(minutes=60):
            raise ValueError("sleep window must be at least 60 minutes")
        if delta > timedelta(hours=24):
            raise ValueError("sleep window must not exceed 24 hours")
        return self


class SleepLogUpdate(BaseModel):
    fell_asleep_at: datetime | None = None
    woke_up_at: datetime | None = None
    rating: SleepRating | None = None
    note: str | None = Field(default=None, max_length=2000)

    def is_empty(self) -> bool:
        return len(self.model_fields_set) == 0


class SleepLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    fell_asleep_at: datetime
    woke_up_at: datetime
    ended_on: date
    total_minutes: int
    rating: str
    note: str | None
    created_at: datetime


class SleepLogList(BaseModel):
    items: list[SleepLogResponse]
```

- [ ] **Step 3: Tests pass**

```bash
poetry run pytest app/tests/test_sleep_log_model.py -v
```

Expected: all PASS.

- [ ] **Step 4: mypy + commit**

```bash
poetry run mypy app/schemas/sleep_logs.py
git add app/schemas/sleep_logs.py app/tests/test_sleep_log_model.py
git commit -m "feat(schemas): SleepLogCreate/Update/Response with window validation"
```

---

## Task 4: Sleep router — full CRUD + latest

**Files:**
- Create: `backend/app/sleep/__init__.py`
- Create: `backend/app/sleep/router.py`
- Modify: `backend/app/main.py`
- Create: `backend/app/tests/test_sleep_logs_router.py`

- [ ] **Step 1: Empty package marker**

```bash
mkdir -p backend/app/sleep
touch backend/app/sleep/__init__.py
```

- [ ] **Step 2: Failing tests**

`backend/app/tests/test_sleep_logs_router.py`:

```python
"""POST/GET/PATCH/DELETE /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.sleep_log import SleepLog


def _payload(ended_on: date = date(2026, 5, 7), **overrides: Any) -> dict[str, Any]:
    body = {
        "fell_asleep_at": datetime(2026, 5, 6, 23, 30, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 7, 7, 15, tzinfo=UTC).isoformat(),
        "ended_on": ended_on.isoformat(),
        "rating": "okay",
    }
    body.update(overrides)
    return body


@pytest.mark.asyncio
async def test_post_creates_sleep_log_with_total_minutes(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()

    resp = await client.post(
        "/api/v1/sleep-logs",
        headers=auth_headers(str(me.supabase_user_id)),
        json=_payload(),
    )
    assert resp.status_code == 201, resp.text
    body = resp.json()
    assert body["rating"] == "okay"
    assert body["total_minutes"] == 7 * 60 + 45  # 23:30 -> 07:15

    refreshed = (
        await db_session.execute(
            select(SleepLog).where(SleepLog.id == uuid.UUID(body["id"]))
        )
    ).scalar_one()
    assert refreshed.user_id == me.id
    assert refreshed.total_minutes == 7 * 60 + 45


@pytest.mark.asyncio
async def test_post_rejects_duplicate_for_same_night(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    first = await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    assert first.status_code == 201

    dupe = await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    assert dupe.status_code == 409


@pytest.mark.asyncio
async def test_get_latest_returns_most_recent_by_ended_on(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    await client.post(
        "/api/v1/sleep-logs",
        headers=headers,
        json=_payload(ended_on=date(2026, 5, 5)),
    )
    await client.post(
        "/api/v1/sleep-logs",
        headers=headers,
        json=_payload(
            ended_on=date(2026, 5, 7),
            fell_asleep_at=datetime(2026, 5, 6, 22, tzinfo=UTC).isoformat(),
            woke_up_at=datetime(2026, 5, 7, 6, 30, tzinfo=UTC).isoformat(),
        ),
    )

    resp = await client.get("/api/v1/sleep-logs/latest", headers=headers)
    assert resp.status_code == 200
    body = resp.json()
    assert body["ended_on"] == "2026-05-07"


@pytest.mark.asyncio
async def test_get_latest_returns_204_when_empty(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.get(
        "/api/v1/sleep-logs/latest",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 204


@pytest.mark.asyncio
async def test_patch_updates_rating(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (
        await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    ).json()

    resp = await client.patch(
        f"/api/v1/sleep-logs/{created['id']}",
        headers=headers,
        json={"rating": "great"},
    )
    assert resp.status_code == 200
    assert resp.json()["rating"] == "great"


@pytest.mark.asyncio
async def test_delete_removes_log(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    created = (
        await client.post("/api/v1/sleep-logs", headers=headers, json=_payload())
    ).json()

    resp = await client.delete(f"/api/v1/sleep-logs/{created['id']}", headers=headers)
    assert resp.status_code == 204

    row = (
        await db_session.execute(
            select(SleepLog).where(SleepLog.id == uuid.UUID(created["id"]))
        )
    ).scalar_one_or_none()
    assert row is None


@pytest.mark.asyncio
async def test_get_404_for_other_user_log(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    other = await make_user()
    other_log = (
        await client.post(
            "/api/v1/sleep-logs",
            headers=auth_headers(str(other.supabase_user_id)),
            json=_payload(),
        )
    ).json()

    resp = await client.get(
        f"/api/v1/sleep-logs/{other_log['id']}",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404
```

```bash
cd backend
poetry run pytest app/tests/test_sleep_logs_router.py -v
```

Expected: FAIL — router doesn't exist.

- [ ] **Step 3: Implement the router**

`backend/app/sleep/router.py`:

```python
"""POST/GET/PATCH/DELETE /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.sleep_log import SleepLog
from app.models.user import User
from app.schemas.sleep_logs import (
    SleepLogCreate,
    SleepLogList,
    SleepLogResponse,
    SleepLogUpdate,
)

router = APIRouter(prefix="/sleep-logs", tags=["sleep"])


@router.post(
    "",
    response_model=SleepLogResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Log last night's sleep",
)
async def create_sleep_log(
    payload: SleepLogCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    row = SleepLog(
        id=uuid.uuid4(),
        user_id=user.id,
        fell_asleep_at=payload.fell_asleep_at,
        woke_up_at=payload.woke_up_at,
        ended_on=payload.ended_on,
        rating=payload.rating,
        note=payload.note,
    )
    db.add(row)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"status": "error", "reason": "sleep_log_for_date_exists"},
        ) from exc
    await db.refresh(row)
    return row


@router.get(
    "/latest",
    response_model=SleepLogResponse | None,
    summary="Most recent sleep log by ended_on; 204 if none",
)
async def latest_sleep_log(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog | Response:
    row = (
        await db.execute(
            select(SleepLog)
            .where(SleepLog.user_id == user.id)
            .order_by(SleepLog.ended_on.desc(), SleepLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    return row


@router.get(
    "",
    response_model=SleepLogList,
    summary="List the caller's sleep logs (newest first)",
)
async def list_sleep_logs(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    start: Annotated[datetime | None, Query()] = None,
    end: Annotated[datetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> SleepLogList:
    stmt = select(SleepLog).where(SleepLog.user_id == user.id)
    if start is not None:
        stmt = stmt.where(SleepLog.fell_asleep_at >= start)
    if end is not None:
        stmt = stmt.where(SleepLog.woke_up_at <= end)
    stmt = stmt.order_by(SleepLog.ended_on.desc()).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    return SleepLogList(items=[SleepLogResponse.model_validate(r) for r in rows])


async def _load(db: AsyncSession, user_id: uuid.UUID, log_id: uuid.UUID) -> SleepLog:
    row = (
        await db.execute(
            select(SleepLog).where(SleepLog.id == log_id, SleepLog.user_id == user_id)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "sleep_log_not_found"},
        )
    return row


@router.get("/{log_id}", response_model=SleepLogResponse)
async def get_sleep_log(
    log_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    return await _load(db, user.id, log_id)


@router.patch(
    "/{log_id}",
    response_model=SleepLogResponse,
    summary="Edit the rating, note, or window of a sleep log",
)
async def patch_sleep_log(
    log_id: uuid.UUID,
    payload: SleepLogUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    row = await _load(db, user.id, log_id)
    if payload.fell_asleep_at is not None:
        row.fell_asleep_at = payload.fell_asleep_at
    if payload.woke_up_at is not None:
        row.woke_up_at = payload.woke_up_at
    if payload.rating is not None:
        row.rating = payload.rating
    if "note" in payload.model_fields_set:
        row.note = payload.note
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "sleep_window_invalid"},
        ) from exc
    await db.refresh(row)
    return row


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sleep_log(
    log_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    row = await _load(db, user.id, log_id)
    await db.delete(row)
    await db.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
```

- [ ] **Step 4: Wire into main.py**

Add `from app.sleep.router import router as sleep_router` and `app.include_router(sleep_router, prefix="/api/v1")` next to the other includes.

- [ ] **Step 5: Run tests**

```bash
cd backend
poetry run pytest app/tests/test_sleep_logs_router.py -v
```

Expected: all 7 PASS.

- [ ] **Step 6: Commit**

```bash
git add app/sleep app/main.py app/tests/test_sleep_logs_router.py
git commit -m "feat(sleep): full CRUD for /api/v1/sleep-logs with daily uniqueness"
```

---

## Task 5: Final verification

- [ ] **Step 1: Migrate test DB**

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
make migrate-test
```

- [ ] **Step 2: Full suite + lint + types + OpenAPI**

```bash
poetry run pytest
poetry run ruff check .
poetry run ruff format --check .
poetry run mypy app/
poetry run python -c "
from app.main import app
schema = app.openapi()
paths = schema['paths']
for p in ('/api/v1/sleep-logs','/api/v1/sleep-logs/latest','/api/v1/sleep-logs/{log_id}'):
    assert p in paths, f'missing {p}'
sl = schema['components']['schemas']['SleepLogResponse']['properties']
for f in ('id','user_id','fell_asleep_at','woke_up_at','ended_on','total_minutes','rating','note','created_at'):
    assert f in sl, f'{f} missing'
print('ok')
"
```

Expected: pytest green (modulo pre-existing APP_VERSION failures), ruff clean, mypy clean, OpenAPI prints `ok`.

- [ ] **Step 3: Format commit if needed**

```bash
git add -A
git diff --cached --quiet && echo "nothing" || git commit -m "chore: ruff format"
```

---

## Done-when

- `sleep_logs` table with generated `total_minutes` exists.
- POST returns `total_minutes` computed by Postgres (not the client) and 409 on second log for the same `ended_on`.
- `GET /sleep-logs/latest` returns the newest by `ended_on`, 204 when empty.
- PATCH updates rating, note, and window; DELETE removes the row.
- `pytest && ruff check && ruff format --check && mypy app/` all green.
- ~5 commits.
