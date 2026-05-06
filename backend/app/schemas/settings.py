"""Pydantic schemas for /api/v1/settings."""

from __future__ import annotations

from datetime import time
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class UserSettingsResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    notification_max_per_day: int
    stress_threshold: float
    quiet_hours_start: time
    quiet_hours_end: time
    silence_during_meeting: bool
    silence_during_exercise: bool
    consent_audit_logging: bool
    language: str


class UserSettingsUpdate(BaseModel):
    notification_max_per_day: int | None = Field(default=None, ge=1, le=10)
    stress_threshold: float | None = Field(default=None, ge=0.0, le=1.0)
    quiet_hours_start: time | None = None
    quiet_hours_end: time | None = None
    silence_during_meeting: bool | None = None
    silence_during_exercise: bool | None = None
    consent_audit_logging: bool | None = None
    language: Literal["ko", "en"] | None = None

    def is_empty(self) -> bool:
        return all(v is None for v in self.model_dump().values())
