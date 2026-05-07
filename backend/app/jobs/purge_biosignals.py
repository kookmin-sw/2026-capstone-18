"""CLI entrypoint: wipe raw biosignals for users with consent_revoked_at set.

Run with:
    poetry run python -m app.jobs.purge_biosignals
"""

from __future__ import annotations

import argparse
import asyncio

import structlog

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.observability.logging import configure_logging
from app.services.deletion import purge_revoked_biosignals

logger = structlog.get_logger(__name__)


async def main() -> int:
    async with AsyncSessionLocal() as db:
        deleted = await purge_revoked_biosignals(db)
        await db.commit()
    logger.info("purge_biosignals_done", users=deleted)
    return deleted


def _cli() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level)
    argparse.ArgumentParser(description="Purge biosignals for revoked users.").parse_args()
    asyncio.run(main())


if __name__ == "__main__":
    _cli()
