"""Pure phase-calculation helper."""

from __future__ import annotations

from datetime import date

import pytest

from app.services.cycle_phase import compute_phase


@pytest.mark.parametrize(
    ("today", "expected_phase", "expected_day"),
    [
        (date(2026, 5, 1), "menstrual", 1),
        (date(2026, 5, 5), "menstrual", 5),
        (date(2026, 5, 6), "follicular", 6),
        (date(2026, 5, 13), "follicular", 13),
        (date(2026, 5, 14), "ovulation", 14),
        (date(2026, 5, 16), "ovulation", 16),
        (date(2026, 5, 17), "luteal", 17),
        (date(2026, 5, 28), "luteal", 28),
    ],
)
def test_compute_phase_typical_28_day_cycle(
    today: date, expected_phase: str, expected_day: int
) -> None:
    phase, day = compute_phase(
        today=today, period_start_date=date(2026, 5, 1), cycle_length_days=28
    )
    assert phase == expected_phase
    assert day == expected_day


def test_compute_phase_returns_pre_period_when_today_is_before_start() -> None:
    phase, day = compute_phase(
        today=date(2026, 4, 30),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    )
    assert phase == "pre_period"
    assert day == 0


def test_compute_phase_after_cycle_length_returns_luteal() -> None:
    """If today is past the predicted cycle length the record is stale; the
    function still returns the post-ovulation phase rather than crash so the
    router can decide what to do (e.g. mark as overdue)."""
    phase, day = compute_phase(
        today=date(2026, 5, 30),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
    )
    assert phase == "luteal"
    assert day == 30


def test_compute_phase_short_cycle_21_days() -> None:
    """Short cycles squeeze luteal phase but follicular/ovulation boundaries
    stay anchored to canonical day numbers."""
    phase, day = compute_phase(
        today=date(2026, 5, 14),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=21,
    )
    assert phase == "ovulation"
    assert day == 14


def test_compute_phase_irregular_cycle_length_below_minimum() -> None:
    """`cycle_length_days` below 14 (extreme outlier) — the helper does not
    raise; it still computes the day count and returns the canonical phase."""
    phase, day = compute_phase(
        today=date(2026, 5, 10),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=12,
    )
    assert phase == "follicular"
    assert day == 10


def test_compute_phase_ongoing_forces_menstrual_past_day_five() -> None:
    """When is_period_ongoing=True, day 8 stays menstrual instead of follicular."""
    phase, day = compute_phase(
        today=date(2026, 5, 8),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=True,
    )
    assert phase == "menstrual"
    assert day == 8


def test_compute_phase_ongoing_within_first_five_days_still_menstrual() -> None:
    phase, day = compute_phase(
        today=date(2026, 5, 3),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=True,
    )
    assert phase == "menstrual"
    assert day == 3


def test_compute_phase_ongoing_does_not_override_pre_period() -> None:
    """A future period_start_date stays pre_period regardless of the flag."""
    phase, day = compute_phase(
        today=date(2026, 4, 30),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=True,
    )
    assert phase == "pre_period"
    assert day == 0


def test_compute_phase_ongoing_false_unchanged_from_default() -> None:
    phase, day = compute_phase(
        today=date(2026, 5, 8),
        period_start_date=date(2026, 5, 1),
        cycle_length_days=28,
        is_period_ongoing=False,
    )
    assert phase == "follicular"
    assert day == 8
