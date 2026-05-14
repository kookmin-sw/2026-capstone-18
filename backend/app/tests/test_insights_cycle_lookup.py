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


def test_classify_returns_pre_period_for_stale_cycle() -> None:
    """User logged a cycle 3 months ago and hasn't logged since.
    Events today must NOT silently classify as 'luteal day 90+' — they should
    fall through to pre_period so phase-grouped aggregates exclude them."""
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    # Cycle started 3 months ago, 28-day length → 1.5x = 42 days stale window
    cycles = [CycleSnapshot(period_start_date=date(2026, 2, 1), cycle_length_days=28)]
    classifier = classify(cycles=cycles)

    # 90 days after Feb 1 is well past 1.5*28=42
    phase, day = classifier(datetime(2026, 5, 2, 12, tzinfo=UTC))
    assert phase == "pre_period"
    assert day == 0


def test_classify_within_staleness_window_uses_cycle() -> None:
    """An event 30 days into a 28-day cycle (within 1.5x window) still classifies
    via compute_phase, even though it's technically past the expected period start."""
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    cycles = [CycleSnapshot(period_start_date=date(2026, 5, 1), cycle_length_days=28)]
    classifier = classify(cycles=cycles)
    # Day 30 of a 28-day cycle: 30 < 42 = 1.5*28, so uses compute_phase
    phase, day = classifier(datetime(2026, 5, 30, 12, tzinfo=UTC))
    assert phase == "luteal"  # day 30 still classifies as luteal via compute_phase
    assert day == 30


def test_is_period_ongoing_overrides_day_based_phase() -> None:
    """A period flagged as still ongoing must stay 'menstrual' past day 5.

    Without this guard, day-11 events get classified as 'follicular' by the
    backend while the frontend (which honors `is_period_ongoing`) correctly
    shows 'menstrual'. That divergence corrupts AI reports + Cycle x Stress.
    """
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    snapshot = CycleSnapshot(
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=True,
    )
    classifier = classify(cycles=[snapshot])

    phase, day = classifier(datetime(2026, 5, 11, 12, 0, tzinfo=UTC))

    assert phase == "menstrual"
    assert day == 11


def test_is_period_ongoing_false_falls_back_to_day_based_phase() -> None:
    """Default behavior (no flag) must still classify day 11 as 'follicular'."""
    from app.services.insights.cycle_lookup import CycleSnapshot, classify

    snapshot = CycleSnapshot(
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=False,
    )
    classifier = classify(cycles=[snapshot])

    phase, day = classifier(datetime(2026, 5, 11, 12, 0, tzinfo=UTC))

    assert phase == "follicular"
    assert day == 11


def test_default_constructor_is_backward_compatible() -> None:
    """Constructing CycleSnapshot without is_period_ongoing must still work."""
    from app.services.insights.cycle_lookup import CycleSnapshot

    snapshot = CycleSnapshot(
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    )
    assert snapshot.is_period_ongoing is False
