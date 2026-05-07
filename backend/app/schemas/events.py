"""Pydantic schemas for stress event endpoints.

Wire format for cursors is opaque to the client. Internally it is the
base64-url-encoding of `<detected_at_iso>|<event_id>` and the router uses it
for keyset pagination ordered by `(detected_at DESC, id DESC)`.
"""

from __future__ import annotations

import base64
import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

USER_RESPONSE_VALUES = ("breathe", "log", "skip", "ignore")
CYCLE_PHASE_VALUES = ("menstrual", "follicular", "ovulation", "luteal")


class StressEventCreate(BaseModel):
    """POST body — client supplies the watch's detection event."""

    detected_at: datetime
    model_confidence: float | None = Field(default=None, ge=0.0, le=1.0)
    user_stress_level: int | None = Field(default=None, ge=0, le=100)
    mood_chips: list[str] | None = None
    category_id: uuid.UUID | None = None
    cycle_phase: Literal["menstrual", "follicular", "ovulation", "luteal"] | None = None
    cycle_day: int | None = Field(default=None, ge=1, le=60)
    logged: bool = False
    log_chips: list[str] | None = None
    log_text: str | None = Field(default=None, max_length=2000)
    notified: bool = False
    user_response: Literal["breathe", "log", "skip", "ignore"] | None = None


class StressEventUpdate(BaseModel):
    """PATCH body — `None` means "leave unchanged"."""

    logged: bool | None = None
    user_stress_level: int | None = Field(default=None, ge=0, le=100)
    mood_chips: list[str] | None = None
    category_id: uuid.UUID | None = None
    log_chips: list[str] | None = None
    log_text: str | None = Field(default=None, max_length=2000)
    user_response: Literal["breathe", "log", "skip", "ignore"] | None = None

    def is_empty(self) -> bool:
        return all(v is None for v in self.model_dump().values())


class StressEventFilter(BaseModel):
    """Query parameters for `GET /events`."""

    model_config = ConfigDict(extra="forbid")

    start: datetime | None = None
    end: datetime | None = None
    logged: bool | None = None
    cycle_phase: Literal["menstrual", "follicular", "ovulation", "luteal"] | None = None
    chip: str | None = Field(default=None, description="Single chip the event must contain")
    cursor: str | None = None
    limit: int = Field(default=50, ge=1, le=200)

    @model_validator(mode="after")
    def _validate_range(self) -> StressEventFilter:
        if self.start is not None and self.end is not None and self.start > self.end:
            raise ValueError("start must be <= end")
        return self


class StressEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    detected_at: datetime
    model_confidence: float | None
    user_stress_level: int | None
    mood_chips: list[str] | None
    category_id: uuid.UUID | None
    cycle_phase: str | None
    cycle_day: int | None
    logged: bool
    log_chips: list[str] | None
    log_text: str | None
    notified: bool
    user_response: str | None
    created_at: datetime


class StressEventList(BaseModel):
    items: list[StressEventResponse]
    next_cursor: str | None = None


def encode_cursor(*, detected_at: datetime, event_id: uuid.UUID) -> str:
    raw = f"{detected_at.isoformat()}|{event_id}".encode()
    return base64.urlsafe_b64encode(raw).rstrip(b"=").decode("ascii")


def decode_cursor(token: str) -> tuple[datetime, uuid.UUID]:
    padding = "=" * (-len(token) % 4)
    try:
        raw = base64.urlsafe_b64decode(token + padding).decode("ascii")
        ts_str, id_str = raw.split("|", 1)
        return datetime.fromisoformat(ts_str), uuid.UUID(id_str)
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError("invalid_cursor") from exc
