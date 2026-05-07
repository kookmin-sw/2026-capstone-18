from __future__ import annotations


def test_response_classes_exist() -> None:
    from app.schemas.dashboard import (
        DashboardCycle,
        DashboardSleep,
        DashboardStress,
        DashboardTodayResponse,
    )

    assert all(
        hasattr(cls, "model_fields")
        for cls in (DashboardCycle, DashboardSleep, DashboardStress, DashboardTodayResponse)
    )


def test_response_serialises_with_all_nulls() -> None:
    from app.schemas.dashboard import DashboardTodayResponse

    body = DashboardTodayResponse.model_validate(
        {
            "stress": None,
            "sleep": None,
            "mood": None,
            "events_count_24h": 0,
            "cycle": None,
        }
    )
    dumped = body.model_dump()
    assert dumped["stress"] is None
    assert dumped["events_count_24h"] == 0
