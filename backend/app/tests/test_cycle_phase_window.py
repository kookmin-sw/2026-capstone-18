"""Unit tests for the phase_window helper."""

from __future__ import annotations

import pytest


def test_phase_window_menstrual_day_1() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="menstrual", day=1, cycle_length_days=28) == 5


def test_phase_window_menstrual_last_day() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="menstrual", day=5, cycle_length_days=28) == 1


def test_phase_window_follicular_first_day() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="follicular", day=6, cycle_length_days=28) == 8


def test_phase_window_ovulation_middle() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="ovulation", day=15, cycle_length_days=28) == 2


def test_phase_window_luteal_uses_cycle_length() -> None:
    from app.services.cycle_phase import phase_window

    # Day 19 of a 28-day cycle: 28 - 19 + 1 = 10 days left
    assert phase_window(phase="luteal", day=19, cycle_length_days=28) == 10


def test_phase_window_luteal_long_cycle() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="luteal", day=20, cycle_length_days=35) == 16


def test_phase_window_luteal_overdue_returns_zero() -> None:
    """If the user is past day cycle_length_days, phase_window must not go negative."""
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="luteal", day=30, cycle_length_days=28) == 0


def test_phase_window_pre_period_returns_none() -> None:
    from app.services.cycle_phase import phase_window

    assert phase_window(phase="pre_period", day=0, cycle_length_days=28) is None


def test_phase_window_unknown_phase_raises() -> None:
    from app.services.cycle_phase import phase_window

    with pytest.raises(ValueError):
        phase_window(phase="weekend", day=1, cycle_length_days=28)
