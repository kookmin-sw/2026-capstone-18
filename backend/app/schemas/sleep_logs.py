"""Wire schemas for /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import date, datetime, timedelta
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

SleepRating = Literal["very_poor", "poor", "okay", "good", "great"]


class SleepLogCreate(BaseModel):
    fell_asleep_at: datetime
    woke_up_at: datetime
    ended_on: date
    rating: SleepRating
    note: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def _validate_window(self) -> SleepLogCreate:
        if self.woke_up_at <= self.fell_asleep_at:
            raise ValueError("woke_up_at must be after fell_asleep_at")
        delta = self.woke_up_at - self.fell_asleep_at
        if delta < timedelta(minutes=60):
            raise ValueError("sleep window must be at least 60 minutes")
        if delta > timedelta(hours=24):
            raise ValueError("sleep window must not exceed 24 hours")
        return self


class SleepLogUpdate(BaseModel):
    fell_asleep_at: datetime | None = None
    woke_up_at: datetime | None = None
    rating: SleepRating | None = None
    note: str | None = Field(default=None, max_length=2000)

    def is_empty(self) -> bool:
        return len(self.model_fields_set) == 0


class SleepLogResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    fell_asleep_at: datetime
    woke_up_at: datetime
    ended_on: date
    total_minutes: int
    rating: str
    note: str | None
    created_at: datetime


class SleepLogList(BaseModel):
    items: list[SleepLogResponse]
