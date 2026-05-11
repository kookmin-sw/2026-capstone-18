"""Compose and push today's morning tip to every opted-in user.

Runs as a daily scheduled job (see app.jobs.send_morning_tips). For each
candidate we either hit the same-day cache or generate a fresh tip via
`MorningTipGenerator`, then push it through FCM. Users with no usable signal
(no sleep, no cycle, no patterns) are silently skipped.

The `fcm_sender` and `generator` callables are injected so tests can
substitute stubs without monkeypatching globals.
"""

from __future__ import annotations

from collections.abc import Awaitable, Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime

import structlog
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.fcm_token import FcmToken
from app.models.user import User
from app.models.user_settings import UserSettings
from app.services.ai.bedrock_client import BedrockError
from app.services.ai.morning_tip import (
    MorningTipGenerator,
    MorningTipUnavailable,
)
from app.services.fcm import send_to_user

logger = structlog.get_logger(__name__)

TIP_TYPE = "tip.morning"


FcmSender = Callable[..., Awaitable[int]]


@dataclass
class MorningTipPushResult:
    candidates: int
    generated: int
    sent: int
    skipped_no_signal: int
    failures: int


async def send_morning_tips(
    db: AsyncSession,
    *,
    fcm_sender: FcmSender = send_to_user,
    generator: MorningTipGenerator | None = None,
    today: date | None = None,
) -> MorningTipPushResult:
    today = today or datetime.now(UTC).date()
    gen = generator or MorningTipGenerator()

    stmt = (
        select(User.id, User.display_name)
        .join(UserSettings, UserSettings.user_id == User.id)
        .where(
            User.deleted_at.is_(None),
            UserSettings.sleep_nudge_enabled.is_(True),
            User.id.in_(select(FcmToken.user_id).distinct()),
        )
    )
    rows = (await db.execute(stmt)).all()
    if not rows:
        return MorningTipPushResult(
            candidates=0, generated=0, sent=0, skipped_no_signal=0, failures=0
        )

    generated = 0
    sent = 0
    skipped = 0
    failed = 0
    for user_id, display_name in rows:
        try:
            tip = await gen.get_or_generate(
                db,
                user_id=user_id,
                display_name=display_name or "사용자",
                today=today,
            )
        except MorningTipUnavailable:
            skipped += 1
            continue
        except BedrockError as exc:
            logger.warning("morning_tip_generate_failed", user_id=str(user_id), error=str(exc))
            failed += 1
            continue
        except Exception as exc:  # noqa: BLE001
            logger.warning("morning_tip_generate_unexpected", user_id=str(user_id), error=str(exc))
            failed += 1
            continue

        generated += 1
        try:
            delivered = await fcm_sender(
                db,
                user_id=user_id,
                payload={
                    "type": TIP_TYPE,
                    "title": tip.headline,
                    "body": tip.body,
                    "context_line": tip.context_line or "",
                    "date": today.isoformat(),
                },
            )
        except Exception as exc:  # noqa: BLE001
            logger.warning("morning_tip_push_failed", user_id=str(user_id), error=str(exc))
            failed += 1
            continue
        if delivered > 0:
            sent += 1

    logger.info(
        "morning_tip_push_completed",
        candidates=len(rows),
        generated=generated,
        sent=sent,
        skipped_no_signal=skipped,
        failures=failed,
        date=today.isoformat(),
    )
    return MorningTipPushResult(
        candidates=len(rows),
        generated=generated,
        sent=sent,
        skipped_no_signal=skipped,
        failures=failed,
    )
