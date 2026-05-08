"""Send sleep-log nudges to opted-in users with no log for last night.

Runs as a once-per-day scheduled job (see app.jobs.send_sleep_nudges). The
sender callable is injected so tests can substitute a stub for the real FCM
client without monkeypatching globals.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

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
