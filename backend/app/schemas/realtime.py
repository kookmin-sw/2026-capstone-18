"""Outbound real-time message envelope."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

OutboundMessageType = Literal[
    "events.created",
    "events.updated",
    "events.deleted",
    "cycles.period_started",
    "settings.updated",
    "system.heartbeat",
]


class OutboundMessage(BaseModel):
    """Wire envelope for every server -> client real-time message."""

    model_config = ConfigDict(use_enum_values=True)

    type: OutboundMessageType
    data: dict[str, Any] = Field(default_factory=dict)
    ts: str = Field(default_factory=lambda: datetime.now(tz=UTC).isoformat())
