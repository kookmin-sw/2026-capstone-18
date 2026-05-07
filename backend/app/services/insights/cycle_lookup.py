"""Build a per-user cycle index → classifier mapping.

We resolve an event's phase by finding the latest period start ≤ the event's
date and applying compute_phase against it.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime

from app.services.cycle_phase import compute_phase


@dataclass(frozen=True)
class CycleSnapshot:
    period_start_date: date
    cycle_length_days: int


PhaseTuple = tuple[str, int]


def classify(*, cycles: list[CycleSnapshot]) -> Callable[[datetime], PhaseTuple]:
    """Return a function that maps a datetime → (phase, day).

    The returned function is pure. It captures `cycles` sorted descending by
    period_start_date; lookup is O(n) but n is small (≤30 typical).
    """
    sorted_cycles = sorted(cycles, key=lambda c: c.period_start_date, reverse=True)

    def _classify(at: datetime) -> PhaseTuple:
        target = at.date()
        for cyc in sorted_cycles:
            if cyc.period_start_date <= target:
                return compute_phase(
                    today=target,
                    period_start_date=cyc.period_start_date,
                    cycle_length_days=cyc.cycle_length_days or 28,
                )
        return ("pre_period", 0)

    return _classify
