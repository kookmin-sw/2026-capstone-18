"""CLI entrypoint: compose and push today's morning tip to opted-in users.

Run with:
    poetry run python -m app.jobs.send_morning_tips

Designed to be invoked once per day around 07:00 KST (22:00 UTC) by
EventBridge Scheduler + ECS RunTask, modeled on send_sleep_nudges.
"""

from __future__ import annotations

import asyncio

import structlog

from app.config import get_settings
from app.db.session import AsyncSessionLocal
from app.observability.logging import configure_logging
from app.services.fcm import init_firebase
from app.services.morning_tip_push import send_morning_tips

logger = structlog.get_logger(__name__)


async def main() -> int:
    settings = get_settings()
    if not settings.ai_features_enabled:
        logger.info("morning_tip_job_skipped_ai_disabled")
        return 0

    init_firebase()
    async with AsyncSessionLocal() as db:
        result = await send_morning_tips(db)
        await db.commit()
    logger.info(
        "send_morning_tips_done",
        candidates=result.candidates,
        generated=result.generated,
        sent=result.sent,
        skipped_no_signal=result.skipped_no_signal,
        failures=result.failures,
    )
    return result.sent


def _cli() -> None:
    settings = get_settings()
    configure_logging(level=settings.log_level)
    asyncio.run(main())


if __name__ == "__main__":
    _cli()
