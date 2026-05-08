"""Wire schemas for /api/v1/reports/drilldown."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class DrilldownSummary(BaseModel):
    category_id: uuid.UUID | None
    category_name: str
    phase: str  # menstrual / follicular / ovulation / luteal
    event_count: int
    avg_stress: float | None
    top_mood: str | None
    most_common_day: int | None
    frm: date
    to: date


class DrilldownHeatmapDay(BaseModel):
    day: int  # cycle day, 1-indexed
    event_count: int
    avg_stress: float | None


class DrilldownEvent(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: uuid.UUID
    detected_at: datetime
    cycle_day: int | None
    user_stress_level: int | None
    top_mood: str | None
    log_text: str | None


class DrilldownResponse(BaseModel):
    summary: DrilldownSummary
    heatmap: list[DrilldownHeatmapDay]
    recent_events: list[DrilldownEvent]
