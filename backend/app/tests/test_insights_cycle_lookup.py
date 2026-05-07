"""Pure-function tests for the cycle classifier."""

from __future__ import annotations

from datetime import UTC, date, datetime


def test_classify_returns_pre_period_when_no_cycles_yet() -> None:
    from app.services.insights.cycle_lookup import classify

    classifier = classify(cycles=[])
    assert classifier(datetime(2026, 5, 6, 12, tzinfo=UTC)) == ("pre_period", 0)


def test_classify_uses_latest_cycle_before_event() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    # May 7 is day 7 of cycle starting May 1 → follicular
    phase, day = classifier(datetime(2026, 5, 7, 12, tzinfo=UTC))
    assert phase == "follicular"
    assert day == 7


def test_classify_for_event_before_first_known_period() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28)]
    classifier = classify(cycles=cycles)
    phase, day = classifier(datetime(2026, 4, 15, 12, tzinfo=UTC))
    assert phase == "pre_period"
    assert day == 0


def test_classify_picks_correct_cycle_when_event_falls_after_two_starts() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 4, 29), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    # April 28 must use the earlier cycle, not the next one starting April 29.
    phase, day = classifier(datetime(2026, 4, 28, 12, tzinfo=UTC))
    assert phase == "luteal"
    assert day == 28


def test_classify_handles_unsorted_input() -> None:
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [
        CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 4, 1), cycle_length_days=28),
        CycleSnapshot(period_start_date=date(2026, 3, 1), cycle_length_days=28),
    ]
    classifier = classify(cycles=cycles)
    phase, day = classifier(datetime(2026, 4, 5, 12, tzinfo=UTC))
    assert phase == "menstrual"
    assert day == 5
