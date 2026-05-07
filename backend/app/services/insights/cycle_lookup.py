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
                length = cyc.cycle_length_days or 28
                # Staleness guard: if the most recent period is more than 1.5x
                # cycle_length stale, treat this event as outside any known
                # cycle. Without this guard, compute_phase silently classifies
                # every event past day 16 as "luteal day N", which corrupts
                # phase-grouped aggregates for users who haven't logged in months.
                days_since = (target - cyc.period_start_date).days
                if days_since > length * 1.5:
                    return ("pre_period", 0)
                return compute_phase(
                    today=target,
                    period_start_date=cyc.period_start_date,
                    cycle_length_days=length,
                )
        return ("pre_period", 0)

    return _classify
