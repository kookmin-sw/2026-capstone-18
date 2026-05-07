"""Smoke test for SleepLog model."""

from __future__ import annotations


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
