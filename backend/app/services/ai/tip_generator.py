"""TipGenerator — produces AI tips for pattern cards with 24h DB cache."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.pattern_tip import PatternTip
from app.services.ai.bedrock_client import BedrockClient
from app.services.ai.prompts import tip_prompt

CACHE_TTL = timedelta(hours=24)
MAX_TIP_TOKENS = 200


class TipGenerator:
    def __init__(self, bedrock: BedrockClient | None = None) -> None:
        self._bedrock = bedrock or BedrockClient()

    async def get_or_generate(
        self,
        db: AsyncSession,
        *,
        user_id: uuid.UUID,
        display_name: str,
        pattern_key: str,
        pattern: dict[str, Any],
    ) -> str:
        existing = (
            await db.execute(
                select(PatternTip).where(
                    PatternTip.user_id == user_id,
                    PatternTip.pattern_key == pattern_key,
                )
            )
        ).scalar_one_or_none()

        now = datetime.now(UTC)
        if existing is not None and (now - existing.generated_at) < CACHE_TTL:
            return existing.tip_text

        system, user = tip_prompt(
            display_name=display_name,
            category_name=pattern["category_name"],
            phase=pattern["phase"],
            delta_pct=float(pattern["delta_pct"]),
            event_count=int(pattern["event_count"]),
            recent_event_lines=list(pattern.get("recent_event_lines") or []),
        )
        tip = (await self._bedrock.invoke(user, system=system, max_tokens=MAX_TIP_TOKENS)).strip()

        if existing is not None:
            existing.tip_text = tip
            existing.generated_at = now
        else:
            db.add(PatternTip(user_id=user_id, pattern_key=pattern_key, tip_text=tip))
        await db.flush()

        return tip
