"""Wire schemas for /api/v1/dashboard/today."""

from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class DashboardStress(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    level: int  # 0-100, the value the home card shows
    source: str  # "user" if user_stress_level, "model" if derived from model_confidence
    detected_at: datetime
    logged: bool


class DashboardSleep(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    total_minutes: int
    rating: str
    ended_on: date


class DashboardCycle(BaseModel):
    phase: str
    day: int
    days_left_in_phase: int | None
    cycle_length_days: int
    period_start_date: date


class DashboardTodayResponse(BaseModel):
    stress: DashboardStress | None
    sleep: DashboardSleep | None
    mood: str | None
    events_count_24h: int
    cycle: DashboardCycle | None
