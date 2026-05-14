"""Build a per-user cycle index → classifier mapping.

We resolve an event's phase by finding the latest period start ≤ the event's
date and applying compute_phase against it.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from datetime import date, datetime
from typing import TYPE_CHECKING

from app.services.cycle_phase import compute_phase

if TYPE_CHECKING:
    from app.models.cycle import Cycle


@dataclass(frozen=True)
class CycleSnapshot:
    period_start_date: date
    cycle_length_days: int
    is_period_ongoing: bool = False
    period_length: int | None = None

    @classmethod
    def from_row(cls, row: Cycle) -> CycleSnapshot:
        """Hydrate from a `cycles` SQLAlchemy row. Derives `period_length` from
        `period_end_date - period_start_date + 1` when `period_end_date` is set,
        else `None` (which falls back to the canonical 5-day menstrual boundary
        in `compute_phase`). Defaults `cycle_length_days` to 28 when null.
        """
        period_length: int | None
        if row.period_end_date is not None and row.period_end_date >= row.period_start_date:
            period_length = (row.period_end_date - row.period_start_date).days + 1
        else:
            period_length = None
        return cls(
            period_start_date=row.period_start_date,
            cycle_length_days=row.cycle_length_days or 28,
            is_period_ongoing=row.is_period_ongoing,
            period_length=period_length,
        )


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
                    is_period_ongoing=cyc.is_period_ongoing,
                    period_length=cyc.period_length,
                )
        return ("pre_period", 0)

    return _classify
