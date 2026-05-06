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
) -> PhaseTuple:
    """Return (phase_name, day_of_cycle).

    `cycle_length_days` is currently unused for boundary calculation — phases
    are anchored to canonical day numbers — but is kept as a parameter so the
    router doesn't have to change when we eventually use it (e.g. to detect
    stale records).
    """
    if today < period_start_date:
        return ("pre_period", 0)
    day = (today - period_start_date).days + 1
    if day <= 5:
        return ("menstrual", day)
    if day <= 13:
        return ("follicular", day)
    if day <= 16:
        return ("ovulation", day)
    return ("luteal", day)
