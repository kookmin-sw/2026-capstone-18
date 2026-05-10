"""Wire schemas for /api/v1/insights/*."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class CalendarDay(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    date: date
    phase: str  # one of menstrual / follicular / ovulation / luteal / pre_period
    event_count: int
    avg_stress: float | None


class InsightsCalendarResponse(BaseModel):
    month: str  # "YYYY-MM"
    days: list[CalendarDay]


class TrendPoint(BaseModel):
    date: date
    avg_stress: float | None
    event_count: int


class InsightsTrendsResponse(BaseModel):
    points: list[TrendPoint]


class PhaseAverage(BaseModel):
    phase: str
    avg_stress: float
    event_count: int


class InsightsPhaseAveragesResponse(BaseModel):
    phases: list[PhaseAverage]


class HeatmapCell(BaseModel):
    phase: str
    count: int


class HeatmapRow(BaseModel):
    category_id: uuid.UUID | None
    category_name: str  # "Uncategorized" if category_id is None
    category_color: str  # "#888888" sentinel for Uncategorized
    cells: list[HeatmapCell]


class InsightsHeatmapResponse(BaseModel):
    rows: list[HeatmapRow]


class PatternCard(BaseModel):
    category_id: uuid.UUID | None
    category_name: str
    phase: str
    category_phase_avg: float
    user_overall_avg: float
    delta_pct: float
    event_count: int


class InsightsPatternsResponse(BaseModel):
    patterns: list[PatternCard]


class PatternTipResponse(BaseModel):
    pattern_key: str
    tip_text: str
    generated_at: datetime
