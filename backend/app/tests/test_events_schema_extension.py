"""Round-trip tests for Plan A schema additions."""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
from pydantic import ValidationError

from app.models.stress_event import StressEvent


def test_model_has_new_columns() -> None:
    """ORM-level smoke check: column attributes exist."""
    assert hasattr(StressEvent, "user_stress_level")
    assert hasattr(StressEvent, "mood_chips")


def test_user_model_has_display_name() -> None:
    from app.models.user import User

    assert hasattr(User, "display_name")


def test_create_schema_validates_stress_level_range() -> None:
    from app.schemas.events import StressEventCreate

    base = {
        "detected_at": datetime(2026, 5, 6, 9, tzinfo=UTC).isoformat(),
    }
    # Lower bound
    StressEventCreate.model_validate({**base, "user_stress_level": 0})
    # Upper bound
    StressEventCreate.model_validate({**base, "user_stress_level": 100})

    with pytest.raises(ValidationError):
        StressEventCreate.model_validate({**base, "user_stress_level": -1})
    with pytest.raises(ValidationError):
        StressEventCreate.model_validate({**base, "user_stress_level": 101})


def test_update_schema_accepts_partial_mood_chips() -> None:
    from app.schemas.events import StressEventUpdate

    upd = StressEventUpdate.model_validate({"mood_chips": ["anxious", "irritated"]})
    assert upd.mood_chips == ["anxious", "irritated"]
    assert upd.is_empty() is False
