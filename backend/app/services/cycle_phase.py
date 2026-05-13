"""Pure phase-calculation helper.

Phase boundaries follow the standard four-phase model. Day numbers are
1-indexed so day 1 is the first day of menstruation. The function never
raises — irregular or stale inputs return canonical phases for the caller
to interpret.
"""

from __future__ import annotations

from datetime import date

PhaseTuple = tuple[str, int]


def compute_phase(
    *,
    today: date,
    period_start_date: date,
    cycle_length_days: int,  # noqa: ARG001 — reserved for future use
    is_period_ongoing: bool = False,
) -> PhaseTuple:
    """Return (phase_name, day_of_cycle).

    `cycle_length_days` is currently unused for boundary calculation — phases
    are anchored to canonical day numbers — but is kept as a parameter so the
    router doesn't have to change when we eventually use it (e.g. to detect
    stale records).

    `is_period_ongoing` overrides the day-based phase: while the user has marked
    their period as still in progress, the phase remains `menstrual` regardless
    of how many days have passed since `period_start_date`. `pre_period` (today
    < period_start_date) is unaffected by the flag.
    """
    if today < period_start_date:
        return ("pre_period", 0)
    day = (today - period_start_date).days + 1
    if is_period_ongoing:
        return ("menstrual", day)
    if day <= 5:
        return ("menstrual", day)
    if day <= 13:
        return ("follicular", day)
    if day <= 16:
        return ("ovulation", day)
    return ("luteal", day)


def phase_window(*, phase: str, day: int, cycle_length_days: int) -> int | None:
    """Return how many days remain in the current phase (1-indexed, inclusive of today).

    For `luteal`, "remaining" is days until next expected period start. Past the
    expected period, returns 0 (don't lie about a negative future).

    For `pre_period`, returns None — the caller should hide the "X days left" badge.
    Raises ValueError on unknown phase strings.
    """
    if phase == "menstrual":
        return max(0, 5 - day + 1)
    if phase == "follicular":
        return max(0, 13 - day + 1)
    if phase == "ovulation":
        return max(0, 16 - day + 1)
    if phase == "luteal":
        return max(0, cycle_length_days - day + 1)
    if phase == "pre_period":
        return None
    raise ValueError(f"unknown phase: {phase!r}")
