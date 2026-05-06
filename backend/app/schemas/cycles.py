"""Pydantic schemas for cycle endpoints.

`CycleImport` is omitted: the historic import flow is deferred until the
phone app actually has data to migrate (post-Sprint 5). Adding it now would
violate YAGNI.
"""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field, model_validator


class CyclePeriodStart(BaseModel):
    """POST body for `POST /api/v1/cycles/period-start`."""

    period_start_date: date
    cycle_length_days: int | None = Field(default=None, ge=14, le=60)
    auto_detected: bool = False


class CycleUpdate(BaseModel):
    """PATCH body for `PATCH /api/v1/cycles/{id}`."""

    period_start_date: date | None = None
    period_end_date: date | None = None
    cycle_length_days: int | None = Field(default=None, ge=14, le=60)

    def is_empty(self) -> bool:
        return all(v is None for v in self.model_dump().values())

    @model_validator(mode="after")
    def _validate_dates(self) -> CycleUpdate:
        if (
            self.period_end_date is not None
            and self.period_start_date is not None
            and self.period_end_date < self.period_start_date
        ):
            raise ValueError("period_end_date must be >= period_start_date")
        return self


class CycleResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    period_start_date: date
    period_end_date: date | None
    cycle_length_days: int | None
    auto_detected: bool
    user_corrected: bool
    created_at: datetime


class CurrentCycleResponse(BaseModel):
    """`GET /api/v1/cycles/current` -- joins the latest cycle row with the
    server-computed phase and day-of-cycle for the caller's local "today"
    (server time, UTC)."""

    cycle: CycleResponse
    phase: str
    day: int
