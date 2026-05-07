from __future__ import annotations

from datetime import date


def test_calendar_response_has_days_array() -> None:
    from app.schemas.insights import CalendarDay, InsightsCalendarResponse

    body = InsightsCalendarResponse.model_validate(
        {
            "month": "2026-05",
            "days": [
                {
                    "date": date(2026, 5, 1).isoformat(),
                    "phase": "menstrual",
                    "event_count": 0,
                    "avg_stress": None,
                },
            ],
        }
    )
    assert body.days[0].phase == "menstrual"
    assert isinstance(body.days[0], CalendarDay)


def test_trends_response_has_series() -> None:
    from app.schemas.insights import InsightsTrendsResponse

    body = InsightsTrendsResponse.model_validate(
        {
            "points": [{"date": "2026-05-01", "avg_stress": 42.0, "event_count": 2}],
        }
    )
    assert body.points[0].avg_stress == 42.0


def test_phase_averages_returns_four_phases_or_subset() -> None:
    from app.schemas.insights import InsightsPhaseAveragesResponse

    body = InsightsPhaseAveragesResponse.model_validate(
        {
            "phases": [
                {"phase": "menstrual", "avg_stress": 32.0, "event_count": 3},
                {"phase": "luteal", "avg_stress": 78.0, "event_count": 12},
            ],
        }
    )
    assert {p.phase for p in body.phases} == {"menstrual", "luteal"}


def test_heatmap_returns_cells_with_counts() -> None:
    from app.schemas.insights import InsightsHeatmapResponse

    body = InsightsHeatmapResponse.model_validate(
        {
            "rows": [
                {
                    "category_id": "00000000-0000-0000-0000-000000000001",
                    "category_name": "Work",
                    "category_color": "#7C3AED",
                    "cells": [
                        {"phase": "menstrual", "count": 2},
                        {"phase": "luteal", "count": 12},
                    ],
                },
            ],
        }
    )
    assert body.rows[0].category_name == "Work"


def test_patterns_returns_cards() -> None:
    from app.schemas.insights import InsightsPatternsResponse

    body = InsightsPatternsResponse.model_validate(
        {
            "patterns": [
                {
                    "category_id": "00000000-0000-0000-0000-000000000001",
                    "category_name": "Work",
                    "phase": "luteal",
                    "category_phase_avg": 74.0,
                    "user_overall_avg": 53.0,
                    "delta_pct": 39.6,
                    "event_count": 12,
                }
            ],
        }
    )
    assert body.patterns[0].delta_pct > 0
