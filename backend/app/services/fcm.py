"""Firebase Cloud Messaging service.

`init_firebase()` is called once at app startup. It loads the service-account
credentials from Settings (in turn from Secrets Manager in staging/prod) and
initializes the global Firebase Admin app. When credentials are absent (e.g.
local dev / tests without monkeypatching), the function is a no-op and
`send_to_user` short-circuits to zero deliveries.

`send_to_user(db, user_id, payload)` looks up every FcmToken for the user,
calls Firebase's multicast API, and removes tokens that come back as
UNREGISTERED.
"""

from __future__ import annotations

import asyncio
import json
import uuid
from typing import Any

import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.models.fcm_token import FcmToken

logger = structlog.get_logger(__name__)

_initialized = False


def init_firebase() -> None:
    """Idempotent. No-op when no credentials are configured."""
    global _initialized
    if _initialized:
        return
    settings = get_settings()
    creds_json = settings.firebase_credentials_json
    if not creds_json:
        logger.info("firebase_init_skipped_no_credentials")
        _initialized = True
        return
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(json.loads(creds_json))
        firebase_admin.initialize_app(cred)
        _initialized = True
        logger.info("firebase_initialized")
    except Exception as exc:  # noqa: BLE001
        logger.error("firebase_init_failed", error=str(exc))
        _initialized = True


def _firebase_send_multicast(multicast: Any) -> Any:
    """Indirection so tests can patch this single call."""
    from firebase_admin import messaging

    return messaging.send_each_for_multicast(multicast)


async def send_to_user(db: AsyncSession, *, user_id: uuid.UUID, payload: dict[str, Any]) -> int:
    """Send `payload` to every token for `user_id`. Returns successful deliveries."""
    tokens_rows = (
        (await db.execute(select(FcmToken).where(FcmToken.user_id == user_id))).scalars().all()
    )
    if not tokens_rows:
        return 0
    tokens = [t.token for t in tokens_rows]

    string_payload = {k: str(v) for k, v in payload.items()}

    try:
        from firebase_admin import messaging

        multicast = messaging.MulticastMessage(tokens=tokens, data=string_payload)
    except ImportError:
        logger.warning("firebase_admin_not_installed")
        return 0

    try:
        response = await asyncio.to_thread(_firebase_send_multicast, multicast)
    except Exception as exc:  # noqa: BLE001
        logger.error("fcm_send_failed", user_id=str(user_id), error=str(exc))
        return 0

    dead_tokens: list[str] = []
    for token, resp in zip(tokens, response.responses, strict=True):
        if not resp.success and resp.exception is not None:
            code = getattr(resp.exception, "code", None)
            if code in {"UNREGISTERED", "INVALID_ARGUMENT"}:
                dead_tokens.append(token)
    if dead_tokens:
        await db.execute(
            delete(FcmToken).where(FcmToken.user_id == user_id, FcmToken.token.in_(dead_tokens))
        )
        await db.flush()
        logger.info("fcm_dead_tokens_pruned", count=len(dead_tokens))

    return int(response.success_count)
