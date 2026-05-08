from __future__ import annotations

from datetime import UTC, date, datetime


def test_drilldown_response_serialises() -> None:
    from app.schemas.reports import (
        DrilldownEvent,
        DrilldownHeatmapDay,
        DrilldownResponse,
        DrilldownSummary,
    )

    body = DrilldownResponse.model_validate(
        {
            "summary": {
                "category_id": None,
                "category_name": "Uncategorized",
                "phase": "luteal",
                "event_count": 12,
                "avg_stress": 74.0,
                "top_mood": "anxious",
                "most_common_day": 20,
                "frm": date(2026, 5, 1).isoformat(),
                "to": date(2026, 9, 30).isoformat(),
            },
            "heatmap": [
                {"day": 17, "event_count": 1, "avg_stress": 60.0},
                {"day": 18, "event_count": 0, "avg_stress": None},
            ],
            "recent_events": [
                {
                    "id": "00000000-0000-0000-0000-000000000001",
                    "detected_at": datetime(2026, 9, 20, 14, 48, tzinfo=UTC).isoformat(),
                    "cycle_day": 20,
                    "user_stress_level": 78,
                    "top_mood": "anxious",
                    "log_text": "Client meeting went long",
                }
            ],
        }
    )
    assert isinstance(body.summary, DrilldownSummary)
    assert isinstance(body.heatmap[0], DrilldownHeatmapDay)
    assert isinstance(body.recent_events[0], DrilldownEvent)
