"""Smoke test for TriggerCategory model."""

from __future__ import annotations

import pytest
from pydantic import ValidationError


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


def test_create_schema_validates_color_hex() -> None:
    from app.schemas.trigger_categories import TriggerCategoryCreate

    TriggerCategoryCreate.model_validate({"name": "Work", "color": "#7C3AED"})
    TriggerCategoryCreate.model_validate({"name": "Work", "color": "#000000"})

    with pytest.raises(ValidationError):
        TriggerCategoryCreate.model_validate({"name": "Work", "color": "purple"})
    with pytest.raises(ValidationError):
        TriggerCategoryCreate.model_validate({"name": "Work", "color": "#FFF"})


def test_create_schema_rejects_blank_name() -> None:
    from app.schemas.trigger_categories import TriggerCategoryCreate

    with pytest.raises(ValidationError):
        TriggerCategoryCreate.model_validate({"name": "", "color": "#7C3AED"})
    with pytest.raises(ValidationError):
        TriggerCategoryCreate.model_validate({"name": "  ", "color": "#7C3AED"})


def test_event_create_accepts_category_id() -> None:
    import uuid as _uuid
    from datetime import UTC, datetime

    from app.schemas.events import StressEventCreate

    cat_id = _uuid.uuid4()
    body = {
        "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
        "category_id": str(cat_id),
    }
    parsed = StressEventCreate.model_validate(body)
    assert parsed.category_id == cat_id
