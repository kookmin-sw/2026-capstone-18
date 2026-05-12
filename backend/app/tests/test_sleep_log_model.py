"""Smoke test for SleepLog model."""

from __future__ import annotations

from datetime import UTC, date, datetime

import pytest
from pydantic import ValidationError


def test_sleep_log_attributes() -> None:
    from app.models.sleep_log import SleepLog

    for attr in (
        "id",
        "user_id",
        "fell_asleep_at",
        "woke_up_at",
        "ended_on",
        "total_minutes",
        "rating",
        "note",
        "created_at",
        "user",
    ):
        assert hasattr(SleepLog, attr), f"missing {attr}"


def test_create_validates_window_order() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    fa = datetime(2026, 5, 6, 23, 30, tzinfo=UTC)
    wu = datetime(2026, 5, 7, 7, 15, tzinfo=UTC)

    SleepLogCreate.model_validate(
        {
            "fell_asleep_at": fa.isoformat(),
            "woke_up_at": wu.isoformat(),
            "ended_on": date(2026, 5, 7).isoformat(),
            "rating": "okay",
        }
    )

    # woke_up_at <= fell_asleep_at must reject
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate(
            {
                "fell_asleep_at": wu.isoformat(),
                "woke_up_at": fa.isoformat(),
                "ended_on": date(2026, 5, 7).isoformat(),
                "rating": "okay",
            }
        )


def test_create_validates_rating_enum() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    base = {
        "fell_asleep_at": datetime(2026, 5, 6, 23, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 7, 7, tzinfo=UTC).isoformat(),
        "ended_on": date(2026, 5, 7).isoformat(),
    }
    SleepLogCreate.model_validate({**base, "rating": "great"})
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate({**base, "rating": "amazing"})


def test_create_caps_window_at_24h() -> None:
    from app.schemas.sleep_logs import SleepLogCreate

    too_long = {
        "fell_asleep_at": datetime(2026, 5, 6, 1, tzinfo=UTC).isoformat(),
        "woke_up_at": datetime(2026, 5, 8, 2, tzinfo=UTC).isoformat(),  # 25h
        "ended_on": date(2026, 5, 8).isoformat(),
        "rating": "okay",
    }
    with pytest.raises(ValidationError):
        SleepLogCreate.model_validate(too_long)


def test_response_rating_rejects_invalid_value() -> None:
    """SleepLogResponse must not accept a rating outside the five valid values.

    Before the fix, rating: str accepts any string; the Pydantic model passes
    "amazing" through silently. After the fix, rating: SleepRating raises.
    """
    import uuid

    from app.schemas.sleep_logs import SleepLogResponse

    valid_data = {
        "id": uuid.uuid4(),
        "user_id": uuid.uuid4(),
        "fell_asleep_at": datetime(2026, 5, 6, 23, 0, tzinfo=UTC),
        "woke_up_at": datetime(2026, 5, 7, 7, 0, tzinfo=UTC),
        "ended_on": date(2026, 5, 7),
        "total_minutes": 480,
        "rating": "great",
        "note": None,
        "created_at": datetime(2026, 5, 7, 7, 0, tzinfo=UTC),
    }
    # Valid rating: must succeed
    SleepLogResponse.model_validate(valid_data)

    # Invalid rating: must raise
    with pytest.raises(ValidationError):
        SleepLogResponse.model_validate({**valid_data, "rating": "amazing"})
