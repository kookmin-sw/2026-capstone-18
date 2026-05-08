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
