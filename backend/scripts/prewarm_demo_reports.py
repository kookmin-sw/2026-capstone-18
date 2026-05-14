"""Pre-generate AI reports for the demo user so /reports/range and
/reports/weekly never have to hit live Bedrock during a presentation.

Run before any demo:

    cd backend && DEMO_USER_ID=<user-uuid> poetry run python scripts/prewarm_demo_reports.py

Reads DEMO_USER_ID from the environment, generates range reports for the
last 7/14/30 days plus the current week's weekly report, and writes them
through to the range_reports / weekly_reports tables. Subsequent API calls
read from the cache and never reach Bedrock.

`DEMO_USER_ID` is the `users.id` UUID (not the Supabase auth.users id).
Look it up with:

    SELECT id FROM users WHERE supabase_user_id = '<supabase-uuid>';
"""

from __future__ import annotations

import asyncio
import os
import sys
import uuid
from datetime import date, timedelta

import structlog
from sqlalchemy import select

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.models.user import User
from app.services.ai.range_report import RangeReportGenerator
from app.services.ai.weekly_report import WeeklyReportGenerator

logger = structlog.get_logger(__name__)


async def _prewarm() -> int:
    raw_id = os.environ.get("DEMO_USER_ID")
    if not raw_id:
        logger.error("DEMO_USER_ID_missing")
        print("ERROR: DEMO_USER_ID env var is required", file=sys.stderr)
        return 2
    try:
        user_id = uuid.UUID(raw_id)
    except ValueError:
        logger.error("DEMO_USER_ID_invalid", value=raw_id)
        print(f"ERROR: DEMO_USER_ID is not a valid UUID: {raw_id}", file=sys.stderr)
        return 2

    settings = get_settings()
    if not settings.ai_features_enabled:
        logger.error("ai_features_disabled")
        print(
            "ERROR: AI features are disabled (settings.ai_features_enabled=False)",
            file=sys.stderr,
        )
        return 3

    today = date.today()
    ranges = [
        (today - timedelta(days=7), today),
        (today - timedelta(days=14), today),
        (today - timedelta(days=30), today),
    ]
    monday_of_this_week = today - timedelta(days=today.weekday())

    async with AsyncSessionLocal() as db:
        user = (await db.execute(select(User).where(User.id == user_id))).scalar_one_or_none()
        if user is None:
            logger.error("demo_user_not_found", user_id=str(user_id))
            print(f"ERROR: no user row for id={user_id}", file=sys.stderr)
            return 4

        range_gen = RangeReportGenerator()
        weekly_gen = WeeklyReportGenerator()

        for frm, to in ranges:
            logger.info("prewarm_range_start", frm=str(frm), to=str(to))
            await range_gen.generate(db, user_id=user.id, period_start=frm, period_end=to)
            await db.commit()
            logger.info("prewarm_range_done", frm=str(frm), to=str(to))

        logger.info("prewarm_weekly_start", week_start=str(monday_of_this_week))
        await weekly_gen.generate(db, user_id=user.id, week_start=monday_of_this_week)
        await db.commit()
        logger.info("prewarm_weekly_done", week_start=str(monday_of_this_week))

    print("OK: prewarm complete", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(_prewarm()))
