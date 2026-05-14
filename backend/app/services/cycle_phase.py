"""Pure phase-calculation helper.

Phase boundaries follow the standard four-phase model. Day numbers are
1-indexed so day 1 is the first day of menstruation. The function never
raises — irregular or stale inputs return canonical phases for the caller
to interpret.
"""

from __future__ import annotations

from datetime import date

PhaseTuple = tuple[str, int]

# Canonical menstrual-phase length used when the user has not logged
# `period_end_date` on the most recent cycle row.
CANONICAL_MENSTRUAL_DAYS = 5


def compute_phase(
    *,
    today: date,
    period_start_date: date,
    cycle_length_days: int,  # noqa: ARG001 — reserved for future use
    is_period_ongoing: bool = False,
    period_length: int | None = None,
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

    `period_length` is the user's actual logged period length in days, derived
    from `period_end_date - period_start_date + 1` at the callsite. When
    provided (and positive) it replaces the canonical 5-day menstrual boundary,
    so the backend classifier matches the frontend insight for users who logged
    a non-default period length. Falls back to ``CANONICAL_MENSTRUAL_DAYS``
    when None or non-positive — backwards-compatible with existing rows that
    never had `period_end_date` set.
    """
    if today < period_start_date:
        return ("pre_period", 0)
    day = (today - period_start_date).days + 1
    if is_period_ongoing:
        return ("menstrual", day)
    menstrual_end = (
        period_length if period_length and period_length > 0 else CANONICAL_MENSTRUAL_DAYS
    )
    if day <= menstrual_end:
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
