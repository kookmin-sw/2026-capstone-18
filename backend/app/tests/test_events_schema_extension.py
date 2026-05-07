"""Round-trip tests for Plan A schema additions."""

from __future__ import annotations

from app.models.stress_event import StressEvent


def test_model_has_new_columns() -> None:
    """ORM-level smoke check: column attributes exist."""
    assert hasattr(StressEvent, "user_stress_level")
    assert hasattr(StressEvent, "mood_chips")


def test_user_model_has_display_name() -> None:
    from app.models.user import User

    assert hasattr(User, "display_name")
