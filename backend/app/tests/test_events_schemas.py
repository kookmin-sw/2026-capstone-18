"""Pydantic schemas + cursor helper for stress events."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest

from app.schemas.events import (
    StressEventCreate,
    StressEventFilter,
    StressEventUpdate,
    decode_cursor,
    encode_cursor,
)


def test_cursor_round_trip() -> None:
    detected = datetime(2026, 5, 6, 12, 0, tzinfo=UTC)
    event_id = uuid.uuid4()
    token = encode_cursor(detected_at=detected, event_id=event_id)
    parsed_at, parsed_id = decode_cursor(token)
    assert parsed_at == detected
    assert parsed_id == event_id


def test_decode_cursor_rejects_garbage() -> None:
    with pytest.raises(ValueError):
        decode_cursor("not-a-real-cursor")


def test_create_validates_user_response_enum() -> None:
    with pytest.raises(ValueError):
        StressEventCreate(
            detected_at=datetime(2026, 5, 6, 12, 0, tzinfo=UTC),
            user_response="explode",
        )


def test_create_accepts_minimal_payload() -> None:
    payload = StressEventCreate(detected_at=datetime(2026, 5, 6, 12, 0, tzinfo=UTC))
    assert payload.logged is False
    assert payload.log_chips is None


def test_update_rejects_empty_body() -> None:
    # PATCH must change at least one field — defended in router, but the schema
    # also exposes a helper for the router to call.
    update = StressEventUpdate()
    assert update.is_empty() is True


def test_filter_rejects_inverted_date_range() -> None:
    with pytest.raises(ValueError):
        StressEventFilter(
            start=datetime(2026, 5, 7, tzinfo=UTC),
            end=datetime(2026, 5, 6, tzinfo=UTC),
        )
