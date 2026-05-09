"""Entrypoint for the EventBridge-triggered weekly reports job.

Usage:
    PYTHONPATH=. uv run python scripts/run_weekly_reports.py
    PYTHONPATH=. uv run python scripts/run_weekly_reports.py --user-id <uuid>
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from app.db.session import AsyncSessionLocal
from app.jobs.weekly_reports_job import run_weekly_reports_job


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--user-id", action="append", default=None)
    args = parser.parse_args()

    async with AsyncSessionLocal() as db:
        summary = await run_weekly_reports_job(
            db,
            user_id_filter=args.user_id,
        )
    print(
        f"weekly_reports_job: users_total={summary.users_total} "
        f"written={summary.reports_written} failed={summary.failures}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    asyncio.run(main())
