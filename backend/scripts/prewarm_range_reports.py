"""Entrypoint for the EventBridge-triggered nightly range-report prewarm job.

Usage:
    PYTHONPATH=. uv run python scripts/prewarm_range_reports.py
    PYTHONPATH=. uv run python scripts/prewarm_range_reports.py --user-id <uuid>

Warms `range_reports` cache for active users (any stress event in the last
30 days) across the canonical 7d/14d/30d ranges. Idempotent — skips rows
whose cached generated_at is already newer than the latest stress event in
the range. Each (user, range) gets its own savepoint, so a single Bedrock
failure cannot fail the whole job.

Exit codes:
    0  job completed (may still have per-user failures — see logs/summary)
    1  uncaught exception (CloudWatch will mark task FAILED → EventBridge
       failure-target → SQS DLQ; ops sees the alarm)
"""

from __future__ import annotations

import argparse
import asyncio
import sys

from app.db.session import AsyncSessionLocal
from app.jobs.prewarm_range_reports_job import run_prewarm_range_reports_job


async def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--user-id",
        action="append",
        default=None,
        help="Filter to specific user UUID(s). Omit to run for all active users.",
    )
    args = parser.parse_args()

    async with AsyncSessionLocal() as db:
        summary = await run_prewarm_range_reports_job(
            db,
            user_id_filter=args.user_id,
        )
    print(
        f"prewarm_range_reports_job: "
        f"users_total={summary.users_total} "
        f"written={summary.reports_written} "
        f"skipped_cache_fresh={summary.reports_skipped_cache_fresh} "
        f"failed={summary.failures}",
        file=sys.stderr,
    )


if __name__ == "__main__":
    asyncio.run(main())
