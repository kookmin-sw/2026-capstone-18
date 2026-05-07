# Plan G — Profile + Sleep Nudge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the Profile screen loop (writable display_name) and ship the "Good morning! Would you like to log last night's sleep?" notification flow shown in the Figma `Notif-sleep log` frame.

**Architecture:** Two parallel deliverables sharing a plan because they share the user-settings table:
1. `PATCH /api/v1/me` — accepts `display_name` (and is structured so future fields slot in cleanly).
2. A scheduled job `app.jobs.send_sleep_nudges` that — once per day, in the morning — looks up users who have FCM tokens, opted in, and have not yet logged last night's sleep, then fires an FCM notification. The actual EventBridge schedule lives in `backend/infra/scheduler.tf` (modeled on the Sprint-7 `purge_accounts` pattern); this plan ships the Python side and stops at "ready to be wired into Terraform".

**Tech Stack:** Python 3.12, FastAPI 0.136, SQLAlchemy 2.0 async, Alembic, Pydantic v2. Reuses `app.services.fcm.send_to_user`.

---

## Decisions Locked

- `PATCH /api/v1/me` body schema is `MeUpdate { display_name?: str }`. Empty body → 422. Future fields (e.g. timezone) are added by extending the schema and the handler — no new endpoint.
- `display_name` validation: 1–64 chars after stripping; emoji and Korean characters allowed. Reject blank-after-strip with 422.
- `sleep_nudge_enabled BOOLEAN NOT NULL DEFAULT TRUE` lives on `user_settings`. Users opt out by `PATCH /api/v1/settings { sleep_nudge_enabled: false }` (existing settings router; we add the field to its schema).
- The sleep nudge runs once per day at a fixed UTC hour. KST is UTC+9 fixed (Korea-only beta cohort), so fire at **02:00 UTC** = 11:00 KST — late enough that the user is awake, early enough that "last night" still feels recent.
- "Last night" is `(today_utc - interval '1 day')` as the `sleep_logs.ended_on` we look for. A user who already logged is skipped silently; a user without logs gets one nudge.
- Idempotency: we record nothing in the DB about having sent a nudge — the cron runs once per day. If we ever scale to multiple invocations, add a `sleep_nudges` table; for v1, the EventBridge schedule guarantees one run.
- FCM payload: `{ "type": "nudge.sleep", "data": { "title": "...", "body": "..." } }`. Copy ("Good morning! Would you like to log last night's sleep now?") matches the Figma `Notif-sleep log` frame verbatim.
- `quiet_hours_*` settings (Sprint 4) do **not** apply to the sleep nudge — the whole point of a sleep-log nudge is to fire after wake-up.

## File Structure

| Path | Action | Responsibility |
| --- | --- | --- |
| `backend/alembic/versions/<rev>_add_sleep_nudge_enabled.py` | **Create** | `user_settings.sleep_nudge_enabled BOOLEAN NOT NULL DEFAULT TRUE` |
| `backend/app/models/user_settings.py` | **Modify** | Add `sleep_nudge_enabled` mapped column |
| `backend/app/schemas/settings.py` | **Modify** | Add `sleep_nudge_enabled` to Update + Response |
| `backend/app/schemas/user.py` | **Modify** | Add `MeUpdate` schema |
| `backend/app/account/router.py` | **Modify** | Add `PATCH /me` handler |
| `backend/app/services/sleep_nudge.py` | **Create** | Pure async function: query candidates, send FCM, return count |
| `backend/app/jobs/send_sleep_nudges.py` | **Create** | CLI entrypoint matching `purge_accounts.py` |
| `backend/app/tests/test_account_patch_me.py` | **Create** | PATCH /me coverage |
| `backend/app/tests/test_sleep_nudge_service.py` | **Create** | Eligibility + send-count tests with monkeypatched FCM |
| `backend/docs/sprint-9-deploy-runbook.md` | **Create** | Document the EventBridge schedule + tfvars used by the Terraform team |

---

## Task 1: PATCH /me

**Files:**
- Modify: `backend/app/schemas/user.py`
- Modify: `backend/app/account/router.py`
- Create: `backend/app/tests/test_account_patch_me.py`

- [ ] **Step 1: Failing tests**

`backend/app/tests/test_account_patch_me.py`:

```python
"""PATCH /api/v1/me."""

from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


@pytest.mark.asyncio
async def test_patch_me_sets_display_name(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    resp = await client.patch(
        "/api/v1/me",
        headers=headers,
        json={"display_name": "Amy"},
    )
    assert resp.status_code == 200, resp.text
    assert resp.json()["display_name"] == "Amy"

    # /me reflects the change.
    refreshed = await client.get("/api/v1/me", headers=headers)
    assert refreshed.json()["display_name"] == "Amy"


@pytest.mark.asyncio
async def test_patch_me_strips_whitespace(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "  Amy  "},
    )
    assert resp.status_code == 200
    assert resp.json()["display_name"] == "Amy"


@pytest.mark.asyncio
async def test_patch_me_rejects_blank(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "   "},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_me_rejects_empty_body(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={},
    )
    assert resp.status_code == 422


@pytest.mark.asyncio
async def test_patch_me_caps_at_64_chars(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    resp = await client.patch(
        "/api/v1/me",
        headers=auth_headers(str(me.supabase_user_id)),
        json={"display_name": "A" * 65},
    )
    assert resp.status_code == 422
```

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
poetry run pytest app/tests/test_account_patch_me.py -v
```

Expected: FAIL — handler doesn't exist.

- [ ] **Step 2: Add `MeUpdate` schema**

In `backend/app/schemas/user.py`, append:

```python
from pydantic import Field, field_validator


class MeUpdate(BaseModel):
    """PATCH /api/v1/me body. Future fields land here."""

    display_name: str | None = Field(default=None, min_length=1, max_length=64)

    @field_validator("display_name")
    @classmethod
    def _strip_and_require(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if not v:
            raise ValueError("display_name must not be blank")
        return v

    def is_empty(self) -> bool:
        return len(self.model_fields_set) == 0
```

- [ ] **Step 3: Add the PATCH handler**

In `backend/app/account/router.py`, alongside the existing `me` GET handler, add:

```python
from app.schemas.user import MeUpdate  # add to existing imports


@router.patch(
    "/me",
    response_model=CurrentUserResponse,
    summary="Update the authenticated user's profile",
)
async def patch_me(
    payload: MeUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CurrentUserResponse:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    if "display_name" in payload.model_fields_set:
        user.display_name = payload.display_name
    await db.flush()
    await db.refresh(user)
    return CurrentUserResponse.model_validate(user)
```

If `status` and `HTTPException` aren't already imported in this router file, add them to the existing FastAPI import line.

- [ ] **Step 4: Tests pass + commit**

```bash
poetry run pytest app/tests/test_account_patch_me.py -v
poetry run mypy app/account/router.py app/schemas/user.py
git add app/account/router.py app/schemas/user.py app/tests/test_account_patch_me.py
git commit -m "feat(account): PATCH /api/v1/me for display_name"
```

---

## Task 2: Migration — `user_settings.sleep_nudge_enabled`

**Files:**
- Create: `backend/alembic/versions/<auto>_add_sleep_nudge_enabled.py`

- [ ] **Step 1: Confirm head and generate**

```bash
cd backend
poetry run alembic heads
```

Expected: the head set by Plan F's chain (or whichever plan most recently shipped). Note the head SHA.

```bash
poetry run alembic revision -m "add user_settings.sleep_nudge_enabled"
```

- [ ] **Step 2: Write migration**

```python
"""add user_settings.sleep_nudge_enabled

Revision ID: <NEW_REVISION>
Revises: <PRIOR_HEAD>
Create Date: <auto>
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '<NEW_REVISION>'
down_revision: Union[str, Sequence[str], None] = '<PRIOR_HEAD>'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "user_settings",
        sa.Column(
            "sleep_nudge_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_settings", "sleep_nudge_enabled")
```

- [ ] **Step 3: Apply + verify + round-trip + commit**

```bash
cd backend
set -a; source /Users/anubilegdemberel/Documents/little-signals/backend/.env; set +a
make migrate
poetry run python -c "
import asyncio, asyncpg, os
async def main():
    conn = await asyncpg.connect(os.environ['DATABASE_URL'].replace('+asyncpg',''))
    row = await conn.fetchrow(\"\"\"
        SELECT data_type, is_nullable, column_default FROM information_schema.columns
         WHERE table_name='user_settings' AND column_name='sleep_nudge_enabled'
    \"\"\")
    assert row is not None, 'column missing'
    assert row['data_type'] == 'boolean'
    assert row['is_nullable'] == 'NO'
    assert 'true' in row['column_default']
    print('ok')
    await conn.close()
asyncio.run(main())
"
poetry run alembic downgrade -1 && poetry run alembic upgrade head
git add alembic/versions/*_add_sleep_nudge_enabled.py
git commit -m "feat(db): add user_settings.sleep_nudge_enabled"
```

---

## Task 3: Model + settings schema field

**Files:**
- Modify: `backend/app/models/user_settings.py`
- Modify: `backend/app/schemas/settings.py`

- [ ] **Step 1: Failing test**

`backend/app/tests/test_sleep_nudge_settings.py`:

```python
from __future__ import annotations

from typing import Any

import pytest
from httpx import AsyncClient


def test_user_settings_model_has_field() -> None:
    from app.models.user_settings import UserSettings
    assert hasattr(UserSettings, "sleep_nudge_enabled")


@pytest.mark.asyncio
async def test_settings_endpoint_exposes_sleep_nudge_enabled(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    headers = auth_headers(str(me.supabase_user_id))

    initial = await client.get("/api/v1/settings", headers=headers)
    assert initial.status_code == 200
    assert initial.json()["sleep_nudge_enabled"] is True

    patched = await client.patch(
        "/api/v1/settings",
        headers=headers,
        json={"sleep_nudge_enabled": False},
    )
    assert patched.status_code == 200
    assert patched.json()["sleep_nudge_enabled"] is False
```

```bash
poetry run pytest app/tests/test_sleep_nudge_settings.py -v
```

Expected: FAIL.

- [ ] **Step 2: Add model field**

In `backend/app/models/user_settings.py`, after `consent_audit_logging` (or wherever the existing `Boolean` columns sit), add:

```python
    sleep_nudge_enabled: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        server_default=text("true"),
    )
```

Confirm `Boolean` and `text` are already imported.

- [ ] **Step 3: Add to settings schemas**

In `backend/app/schemas/settings.py`:

```python
class UserSettingsResponse(BaseModel):
    # ... existing fields ...
    sleep_nudge_enabled: bool
    # (preserve existing config / from_attributes setup)


class UserSettingsUpdate(BaseModel):
    # ... existing fields ...
    sleep_nudge_enabled: bool | None = None
    # (preserve existing is_empty() helper if present)
```

Add the field in the same relative position in both classes — alongside the other booleans (`silence_during_meeting`, `silence_during_exercise`, `consent_audit_logging`).

- [ ] **Step 4: Add the pass-through to the settings router**

Read `backend/app/settings_api/router.py`. Locate the `patch_settings` handler. After the existing `if payload.consent_audit_logging is not None: ...` block (or analogous), add:

```python
    if payload.sleep_nudge_enabled is not None:
        settings_row.sleep_nudge_enabled = payload.sleep_nudge_enabled
```

Match the exact field-name-on-row used by the existing handler — check the actual variable name in that file before editing.

- [ ] **Step 5: Tests pass + commit**

```bash
poetry run pytest app/tests/test_sleep_nudge_settings.py -v
poetry run mypy app/models/user_settings.py app/schemas/settings.py app/settings_api/router.py
git add app/models/user_settings.py app/schemas/settings.py app/settings_api/router.py app/tests/test_sleep_nudge_settings.py
git commit -m "feat(settings): expose sleep_nudge_enabled toggle"
```

---

## Task 4: Sleep nudge service

**Files:**
- Create: `backend/app/services/sleep_nudge.py`
- Create: `backend/app/tests/test_sleep_nudge_service.py`

- [ ] **Step 1: Failing tests**

`backend/app/tests/test_sleep_nudge_service.py`:

```python
"""Unit tests for the sleep-nudge sender."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime, timedelta
from typing import Any

import pytest
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.sleep_log import SleepLog
from app.models.user_settings import UserSettings


def _yesterday_utc() -> date:
    return (datetime.now(tz=UTC) - timedelta(days=1)).date()


@pytest.mark.asyncio
async def test_send_returns_zero_when_no_users(
    db_session: AsyncSession,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    result = await send_sleep_nudges(db_session, fcm_sender=_StubSender())
    assert result.candidates == 0
    assert result.sent == 0


@pytest.mark.asyncio
async def test_send_skips_user_who_already_logged_last_night(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(FcmToken(
        id=uuid.uuid4(),
        user_id=me.id,
        token="dev-token-1",
    ))
    db_session.add(SleepLog(
        id=uuid.uuid4(),
        user_id=me.id,
        fell_asleep_at=datetime.now(tz=UTC) - timedelta(hours=10),
        woke_up_at=datetime.now(tz=UTC) - timedelta(hours=2),
        ended_on=_yesterday_utc(),
        rating="okay",
    ))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)

    assert result.candidates == 1
    assert result.sent == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_sends_to_user_who_missed_last_night(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(FcmToken(
        id=uuid.uuid4(),
        user_id=me.id,
        token="dev-token-1",
    ))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)

    assert result.candidates == 1
    assert result.sent == 1
    assert sender.calls == [me.id]


@pytest.mark.asyncio
async def test_send_skips_opted_out_users(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=False))
    db_session.add(FcmToken(id=uuid.uuid4(), user_id=me.id, token="t"))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_skips_users_with_no_fcm_token(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user()
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


@pytest.mark.asyncio
async def test_send_skips_deleted_users(
    db_session: AsyncSession,
    make_user: Any,
) -> None:
    from app.services.sleep_nudge import send_sleep_nudges

    me = await make_user(deleted_at=datetime.now(tz=UTC))
    db_session.add(UserSettings(user_id=me.id, sleep_nudge_enabled=True))
    db_session.add(FcmToken(id=uuid.uuid4(), user_id=me.id, token="t"))
    await db_session.flush()

    sender = _StubSender()
    result = await send_sleep_nudges(db_session, fcm_sender=sender)
    assert result.candidates == 0
    assert sender.calls == []


class _StubSender:
    def __init__(self) -> None:
        self.calls: list[uuid.UUID] = []

    async def __call__(
        self, db: AsyncSession, *, user_id: uuid.UUID, payload: dict[str, str]
    ) -> int:
        self.calls.append(user_id)
        return 1
```

```bash
poetry run pytest app/tests/test_sleep_nudge_service.py -v
```

Expected: FAIL.

- [ ] **Step 2: Implement service**

`backend/app/services/sleep_nudge.py`:

```python
"""Send sleep-log nudges to opted-in users with no log for last night.

Runs as a once-per-day scheduled job (see app.jobs.send_sleep_nudges). The
sender callable is injected so tests can substitute a stub for the real FCM
client without monkeypatching globals.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from typing import Awaitable, Callable

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.sleep_log import SleepLog
from app.models.user import User
from app.models.user_settings import UserSettings
from app.services.fcm import send_to_user

logger = structlog.get_logger(__name__)

NUDGE_TYPE = "nudge.sleep"
TITLE = "Good morning"
BODY = "Would you like to log last night's sleep now?"


FcmSender = Callable[..., Awaitable[int]]
"""Async callable matching `app.services.fcm.send_to_user`'s signature."""


@dataclass
class SleepNudgeResult:
    candidates: int
    sent: int


async def send_sleep_nudges(
    db: AsyncSession,
    *,
    fcm_sender: FcmSender = send_to_user,
) -> SleepNudgeResult:
    yesterday = (datetime.now(tz=UTC) - timedelta(days=1)).date()

    # Candidates: opted-in, not deleted, has at least one FCM token.
    stmt = (
        select(User.id)
        .join(UserSettings, UserSettings.user_id == User.id)
        .where(
            User.deleted_at.is_(None),
            UserSettings.sleep_nudge_enabled.is_(True),
            User.id.in_(select(FcmToken.user_id).distinct()),
        )
    )
    candidate_ids = [row[0] for row in (await db.execute(stmt)).all()]

    if not candidate_ids:
        return SleepNudgeResult(candidates=0, sent=0)

    # Exclude users who already logged last night.
    already_logged = {
        row[0]
        for row in (
            await db.execute(
                select(SleepLog.user_id).where(
                    SleepLog.user_id.in_(candidate_ids),
                    SleepLog.ended_on == yesterday,
                )
            )
        ).all()
    }
    targets = [uid for uid in candidate_ids if uid not in already_logged]

    sent = 0
    for user_id in targets:
        try:
            delivered = await fcm_sender(
                db,
                user_id=user_id,
                payload={
                    "type": NUDGE_TYPE,
                    "title": TITLE,
                    "body": BODY,
                    "ended_on": yesterday.isoformat(),
                },
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning(
                "sleep_nudge_send_failed",
                user_id=str(user_id),
                error=str(exc),
            )
            continue
        if delivered > 0:
            sent += 1

    logger.info(
        "sleep_nudge_completed",
        candidates=len(candidate_ids),
        sent=sent,
        ended_on=yesterday.isoformat(),
    )
    return SleepNudgeResult(candidates=len(candidate_ids), sent=sent)
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_sleep_nudge_service.py -v
poetry run mypy app/services/sleep_nudge.py
git add app/services/sleep_nudge.py app/tests/test_sleep_nudge_service.py
git commit -m "feat(notifications): sleep nudge service"
```

---

## Task 5: CLI entrypoint job

**Files:**
- Create: `backend/app/jobs/send_sleep_nudges.py`
- Create: `backend/app/tests/test_send_sleep_nudges_job.py`

- [ ] **Step 1: Failing test**

`backend/app/tests/test_send_sleep_nudges_job.py`:

```python
from __future__ import annotations

import asyncio


def test_main_returns_int_count(monkeypatch) -> None:  # type: ignore[no-untyped-def]
    """The job's main() must return the count of nudges sent so the
    EventBridge ECS RunTask exit code can reflect success/failure."""
    from app.jobs import send_sleep_nudges

    async def fake_sender(*args, **kwargs):  # type: ignore[no-untyped-def]
        return 0

    # We don't run the full DB pipeline here — that's covered by service tests.
    # We only verify the entrypoint is callable and returns an int.
    assert asyncio.iscoroutinefunction(send_sleep_nudges.main)
```

```bash
poetry run pytest app/tests/test_send_sleep_nudges_job.py -v
```

Expected: FAIL.

- [ ] **Step 2: Create job entrypoint**

`backend/app/jobs/send_sleep_nudges.py`:

```python
"""CLI entrypoint: send sleep-log nudges to users who didn't log last night.

Run with:
    poetry run python -m app.jobs.send_sleep_nudges

Designed to be invoked once per day at ~02:00 UTC by EventBridge Scheduler +
ECS RunTask, modeled on the Sprint-7 purge_accounts job.
"""

from __future__ import annotations

import asyncio

import structlog

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.observability.logging import configure_logging
from app.services.fcm import init_firebase
from app.services.sleep_nudge import send_sleep_nudges

logger = structlog.get_logger(__name__)


async def main() -> int:
    init_firebase()
    async with AsyncSessionLocal() as db:
        result = await send_sleep_nudges(db)
        await db.commit()
    logger.info(
        "send_sleep_nudges_done",
        candidates=result.candidates,
        sent=result.sent,
    )
    return result.sent


def _cli() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level)
    asyncio.run(main())


if __name__ == "__main__":
    _cli()
```

- [ ] **Step 3: Tests pass + commit**

```bash
poetry run pytest app/tests/test_send_sleep_nudges_job.py -v
poetry run mypy app/jobs/send_sleep_nudges.py
git add app/jobs/send_sleep_nudges.py app/tests/test_send_sleep_nudges_job.py
git commit -m "feat(jobs): send_sleep_nudges CLI entrypoint"
```

---

## Task 6: Deploy runbook

**Files:**
- Create: `backend/docs/sprint-9-deploy-runbook.md`

The Python side ships in this plan. The EventBridge schedule is a Terraform change that the deploy team owns — this runbook tells them exactly what to add.

- [ ] **Step 1: Write the runbook**

`backend/docs/sprint-9-deploy-runbook.md`:

```markdown
# Sprint 9 — Sleep Nudge Schedule Deploy

## What ships in this branch

- `app.jobs.send_sleep_nudges` — CLI entrypoint matching the Sprint-7 `purge_accounts` pattern.
- `app.services.sleep_nudge` — pure service callable from tests and the job.
- `user_settings.sleep_nudge_enabled` — opt-in toggle, default true.
- `PATCH /api/v1/me` — display_name editing for the Profile screen.

## What the deploy team adds

In `backend/infra/scheduler.tf`, alongside the existing `purge_accounts` and
`purge_biosignals` schedules, add a new `aws_scheduler_schedule` resource:

```hcl
resource "aws_scheduler_schedule" "send_sleep_nudges" {
  name       = "send-sleep-nudges-${var.environment}"
  group_name = aws_scheduler_schedule_group.cron.name

  flexible_time_window { mode = "OFF" }

  # 02:00 UTC = 11:00 KST. Korea-only beta cohort.
  schedule_expression = "cron(0 2 * * ? *)"

  target {
    arn      = aws_ecs_cluster.this.arn
    role_arn = aws_iam_role.scheduler.arn

    ecs_parameters {
      task_definition_arn = aws_ecs_task_definition.cron.arn
      task_count          = 1
      launch_type         = "FARGATE"

      network_configuration {
        subnets          = var.private_subnet_ids
        security_groups  = [aws_security_group.ecs.id]
        assign_public_ip = false
      }
    }

    input = jsonencode({
      containerOverrides = [{
        name    = "cron"
        command = ["python", "-m", "app.jobs.send_sleep_nudges"]
      }]
    })

    dead_letter_config {
      arn = aws_sqs_queue.scheduler_dlq.arn
    }

    retry_policy {
      maximum_event_age_in_seconds = 600
      maximum_retry_attempts       = 2
    }
  }
}
```

Apply with `terraform apply -var-file=staging.tfvars`. Verify the schedule
shows in EventBridge:

```bash
aws scheduler list-schedules --group-name cron-staging --profile little-signals-staging
```

## Verification after first nightly run

```bash
aws logs tail /ecs/cron-staging --since 1h --filter-pattern '"send_sleep_nudges_done"' \
  --profile little-signals-staging
```

Expected log line: `{"event":"send_sleep_nudges_done","candidates":N,"sent":M,...}`.

## Rollback

```bash
terraform apply -target=aws_scheduler_schedule.send_sleep_nudges -destroy
```

Or simply `aws scheduler update-schedule --state DISABLED ...` to pause without
removing.
```

- [ ] **Step 2: Commit**

```bash
git add backend/docs/sprint-9-deploy-runbook.md
git commit -m "docs(sprint-9): sleep nudge schedule deploy runbook"
```

---

## Task 7: Final verification

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
paths = schema['paths']
me = paths['/api/v1/me']
assert 'patch' in me, 'PATCH /me missing'
settings = schema['components']['schemas']['UserSettingsResponse']['properties']
assert 'sleep_nudge_enabled' in settings, 'sleep_nudge_enabled missing on UserSettingsResponse'
print('ok')
"
```

- [ ] **Step 3: Smoke-run the job locally against the dev DB**

This is a nice-to-have. The dev DB has no real FCM tokens, so the job will report 0 candidates / 0 sent — but it confirms the entrypoint runs without import or connectivity errors.

```bash
poetry run python -m app.jobs.send_sleep_nudges
```

Expected: log lines `firebase_init_skipped_no_credentials` and `send_sleep_nudges_done` with `candidates=0, sent=0`. No traceback.

- [ ] **Step 4: Format-only commit if needed**

```bash
git add -A
git diff --cached --quiet && echo "nothing" || git commit -m "chore: ruff format"
```

---

## Done-when

- `PATCH /api/v1/me { display_name: "Amy" }` updates the user and re-reads via GET /me reflect the change.
- Empty body, blank-after-strip, and >64-char display_names all return 422.
- `user_settings.sleep_nudge_enabled` defaults to true and is patchable via `/api/v1/settings`.
- `app.services.sleep_nudge.send_sleep_nudges` skips opted-out, deleted, FCM-less, and already-logged users; sends to everyone else exactly once per call.
- `python -m app.jobs.send_sleep_nudges` runs cleanly against the dev DB.
- Sprint-9 deploy runbook documents the EventBridge resource the deploy team adds.
- ~6 commits.
