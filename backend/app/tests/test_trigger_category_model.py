"""Smoke test for TriggerCategory model."""

from __future__ import annotations


def test_trigger_category_attributes() -> None:
    from app.models.trigger_category import TriggerCategory

    for attr in (
        "id",
        "user_id",
        "name",
        "color",
        "sort_order",
        "archived_at",
        "created_at",
        "user",
    ):
        assert hasattr(TriggerCategory, attr), f"missing {attr}"


def test_stress_event_has_category_id() -> None:
    from app.models.stress_event import StressEvent

    assert hasattr(StressEvent, "category_id")
