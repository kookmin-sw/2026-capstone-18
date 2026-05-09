"""One-shot seed script for the demo user with 6 months of synthetic data.

Usage:
    cd backend
    uv run python scripts/seed_demo_user.py

The script:
  1. Signs up (or logs in) the demo user against staging via the public auth API.
  2. Decodes the access token to extract the Supabase user id.
  3. Connects to staging RDS using the same DATABASE_URL as the backend.
  4. Wipes any prior seed rows for that user, then writes 6 months of cycles,
     sleep logs, stress events, raw-biosignal upload references, and trigger
     categories. Deterministic via random.Random(42).
"""

from __future__ import annotations

import asyncio
import base64
import json
import random
import uuid
from datetime import UTC, date, datetime, time, timedelta

import httpx
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.config import get_settings
from app.models.cycle import Cycle
from app.models.raw_biosignal_upload import RawBiosignalUpload
from app.models.sleep_log import SleepLog
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.models.user import User
from app.services.user_settings import ensure_user_settings

API_BASE = "https://api-staging.friendlykr.com"
EMAIL = "anu.bn@yahoo.com"
PASSWORD = "Password123!"  # noqa: S105  (demo credential, intentional)
DISPLAY_NAME = "이현이"
TODAY = date(2026, 5, 10)
DAYS_BACK = 180

CATEGORIES: list[tuple[str, str]] = [
    ("업무", "#E57373"),
    ("가족", "#F06292"),
    ("수면 부족", "#9575CD"),
    ("운동", "#64B5F6"),
    ("사회적 관계", "#4DB6AC"),
    ("기타", "#A1887F"),
]


def _b64url_decode(segment: str) -> bytes:
    """Decode a base64url JWT segment, padding as needed."""
    padding = "=" * (-len(segment) % 4)
    return base64.urlsafe_b64decode(segment + padding)


def decode_jwt_sub(token: str) -> uuid.UUID:
    """Pull `sub` (the Supabase user id) out of an unverified JWT."""
    parts = token.split(".")
    if len(parts) != 3:
        raise ValueError("Token is not a JWT")
    payload = json.loads(_b64url_decode(parts[1]))
    return uuid.UUID(payload["sub"])


def auth_signup_or_login() -> tuple[str, uuid.UUID]:
    """Sign up the demo user; if the email already exists, log in instead.

    Returns the access token and the decoded Supabase user id.
    """
    with httpx.Client(base_url=API_BASE, timeout=30.0) as client:
        signup = client.post(
            "/api/v1/auth/email/signup",
            json={
                "email": EMAIL,
                "password": PASSWORD,
                "display_name": DISPLAY_NAME,
            },
        )
        if signup.status_code == 409:
            login = client.post(
                "/api/v1/auth/email/login",
                json={"email": EMAIL, "password": PASSWORD},
            )
            login.raise_for_status()
            data = login.json()
        else:
            signup.raise_for_status()
            data = signup.json()

    token = data.get("access_token") or data["session"]["access_token"]
    return token, decode_jwt_sub(token)


def build_cycles(rng: random.Random, user_id: uuid.UUID) -> list[Cycle]:
    """Walk back from TODAY emitting cycles of 28+/-2 days, periods 4-6 days."""
    cycles: list[Cycle] = []
    start_floor = TODAY - timedelta(days=DAYS_BACK)
    next_period_start = TODAY - timedelta(days=rng.randint(0, 5))
    while next_period_start >= start_floor:
        period_len = rng.randint(4, 6)
        cycle_len = 28 + rng.randint(-2, 2)
        cycles.append(
            Cycle(
                user_id=user_id,
                period_start_date=next_period_start,
                period_end_date=next_period_start + timedelta(days=period_len - 1),
                cycle_length_days=cycle_len,
                auto_detected=False,
                user_corrected=True,
            )
        )
        next_period_start = next_period_start - timedelta(days=cycle_len)
    return cycles


def build_sleep_logs(rng: random.Random, user_id: uuid.UUID) -> list[SleepLog]:
    """One sleep log per day across the seed range."""
    logs: list[SleepLog] = []
    for offset in range(DAYS_BACK + 1):
        day = TODAY - timedelta(days=DAYS_BACK - offset)
        # fell_asleep between 22:30 of (day-1) and 01:30 of day, in UTC.
        minutes_after_2230 = rng.randint(0, 180)
        bed_anchor = datetime.combine(day - timedelta(days=1), time(22, 30), tzinfo=UTC)
        fell_asleep = bed_anchor + timedelta(minutes=minutes_after_2230)
        sleep_minutes = rng.randint(6 * 60, 9 * 60)
        woke_up = fell_asleep + timedelta(minutes=sleep_minutes)
        weekday = day.weekday()  # Mon=0, Tue=1
        score = 75 + rng.randint(-10, 10) - (5 if weekday in (0, 1) else 0)
        if score >= 80:
            rating = "great"
        elif score >= 60:
            rating = "ok"
        else:
            rating = "rough"
        logs.append(
            SleepLog(
                user_id=user_id,
                fell_asleep_at=fell_asleep,
                woke_up_at=woke_up,
                ended_on=woke_up.date(),
                rating=rating,
            )
        )
    return logs


def build_stress_events(
    rng: random.Random,
    user_id: uuid.UUID,
    category_ids: list[uuid.UUID],
) -> list[StressEvent]:
    """~3 days/week with 1-2 events each, on plausible hour buckets."""
    events: list[StressEvent] = []
    hour_buckets = [9, 11, 14, 16, 19, 21]
    for offset in range(DAYS_BACK + 1):
        if rng.random() > 3 / 7:
            continue
        day = TODAY - timedelta(days=DAYS_BACK - offset)
        n = rng.randint(1, 2)
        chosen_hours = rng.sample(hour_buckets, n)
        for hour in chosen_hours:
            detected_at = datetime.combine(day, time(hour, rng.randint(0, 59)), tzinfo=UTC)
            events.append(
                StressEvent(
                    user_id=user_id,
                    detected_at=detected_at,
                    model_confidence=round(rng.uniform(0.6, 0.95), 2),
                    user_stress_level=rng.randint(1, 5),
                    category_id=rng.choice(category_ids),
                    logged=True,
                    notified=True,
                )
            )
    return events


def build_biosignal_uploads(rng: random.Random, user_id: uuid.UUID) -> list[RawBiosignalUpload]:
    """Two uploads per day (hrv + heart_rate) with synthetic S3 keys."""
    uploads: list[RawBiosignalUpload] = []
    for offset in range(DAYS_BACK + 1):
        day = TODAY - timedelta(days=DAYS_BACK - offset)
        for signal_type in ("hrv", "heart_rate"):
            recorded_at = datetime.combine(
                day,
                time(rng.randint(8, 22), rng.randint(0, 59)),
                tzinfo=UTC,
            )
            key = f"users/{user_id}/biosignals/{day.isoformat()}/seed-{uuid.uuid4()}.bin"
            uploads.append(
                RawBiosignalUpload(
                    user_id=user_id,
                    s3_object_key=key,
                    signal_type=signal_type,
                    recorded_at=recorded_at,
                )
            )
    return uploads


async def seed(supabase_user_id: uuid.UUID) -> None:
    settings = get_settings()
    engine = create_async_engine(settings.database_url, echo=False)
    session_maker = async_sessionmaker(engine, expire_on_commit=False)

    rng = random.Random(42)

    async with session_maker() as db:
        user = (
            await db.execute(select(User).where(User.supabase_user_id == supabase_user_id))
        ).scalar_one_or_none()
        if user is None:
            raise RuntimeError(
                f"User row not found for supabase_user_id={supabase_user_id}; "
                "the auth handler should have created it."
            )

        user.display_name = DISPLAY_NAME
        user.consent_raw_biosignals = True
        await db.flush()
        await ensure_user_settings(db, user)

        # Wipe prior seed data (cascade is at the user level, but the user is
        # kept — delete child rows directly).
        await db.execute(delete(RawBiosignalUpload).where(RawBiosignalUpload.user_id == user.id))
        await db.execute(delete(StressEvent).where(StressEvent.user_id == user.id))
        await db.execute(delete(SleepLog).where(SleepLog.user_id == user.id))
        await db.execute(delete(Cycle).where(Cycle.user_id == user.id))
        await db.execute(delete(TriggerCategory).where(TriggerCategory.user_id == user.id))
        await db.flush()

        categories = [
            TriggerCategory(
                user_id=user.id,
                name=name,
                color=color,
                sort_order=idx,
            )
            for idx, (name, color) in enumerate(CATEGORIES)
        ]
        db.add_all(categories)
        await db.flush()
        category_ids = [cat.id for cat in categories]

        cycles = build_cycles(rng, user.id)
        db.add_all(cycles)

        sleep_logs = build_sleep_logs(rng, user.id)
        db.add_all(sleep_logs)

        stress_events = build_stress_events(rng, user.id, category_ids)
        db.add_all(stress_events)

        uploads = build_biosignal_uploads(rng, user.id)
        db.add_all(uploads)

        await db.commit()

        print("Seed complete:")
        print(f"  user_id              = {user.id}")
        print(f"  supabase_user_id     = {user.supabase_user_id}")
        print(f"  trigger_categories   = {len(categories)}")
        print(f"  cycles               = {len(cycles)}")
        print(f"  sleep_logs           = {len(sleep_logs)}")
        print(f"  stress_events        = {len(stress_events)}")
        print(f"  raw_biosignal_uploads= {len(uploads)}")

    await engine.dispose()


def main() -> None:
    print(f"Authenticating demo user {EMAIL} against {API_BASE} ...")
    _token, supabase_user_id = auth_signup_or_login()
    print(f"  supabase_user_id = {supabase_user_id}")
    asyncio.run(seed(supabase_user_id))
    print()
    print("Demo credentials:")
    print(f"  email        = {EMAIL}")
    print(f"  password     = {PASSWORD}")
    print(f"  display_name = {DISPLAY_NAME}")


if __name__ == "__main__":
    main()
