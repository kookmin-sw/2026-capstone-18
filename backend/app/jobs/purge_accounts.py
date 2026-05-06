"""CLI entrypoint: hard-delete soft-deleted users past the grace window.

Run with:
    poetry run python -m app.jobs.purge_accounts [--grace-window-days N]

Used for one-off operator runs. The hourly background loop in app.main
covers the regular schedule.
"""

from __future__ import annotations

import argparse
import asyncio

import structlog

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.observability.logging import configure_logging
from app.services.deletion import purge_expired_accounts

logger = structlog.get_logger(__name__)


async def main(*, grace_window_days: int) -> int:
    async with AsyncSessionLocal() as db:
        deleted = await purge_expired_accounts(db, grace_window_days=grace_window_days)
        await db.commit()
    logger.info("purge_accounts_done", deleted=deleted)
    return deleted


def _cli() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level)
    parser = argparse.ArgumentParser(description="Hard-delete expired accounts.")
    parser.add_argument(
        "--grace-window-days",
        type=int,
        default=settings.account_grace_window_days,
    )
    args = parser.parse_args()
    asyncio.run(main(grace_window_days=args.grace_window_days))


if __name__ == "__main__":
    _cli()
