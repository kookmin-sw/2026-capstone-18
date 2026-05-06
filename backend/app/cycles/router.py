"""POST/GET/PATCH /api/v1/cycles/*."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.cycle import Cycle
from app.models.user import User
from app.schemas.cycles import (
    CurrentCycleResponse,
    CyclePeriodStart,
    CycleResponse,
    CycleUpdate,
)
from app.services.cycle_phase import compute_phase

router = APIRouter(prefix="/cycles", tags=["cycles"])


def _today() -> date:
    """Indirection so tests can monkeypatch a stable "today"."""
    return datetime.now(tz=UTC).date()


@router.post(
    "/period-start",
    response_model=CycleResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Log the start of a period",
)
async def period_start(
    payload: CyclePeriodStart,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Cycle:
    cycle = Cycle(
        user_id=user.id,
        period_start_date=payload.period_start_date,
        cycle_length_days=payload.cycle_length_days,
        auto_detected=payload.auto_detected,
    )
    db.add(cycle)
    await db.flush()
    await db.refresh(cycle)
    return cycle


@router.get(
    "/current",
    response_model=CurrentCycleResponse,
    summary="Current cycle: latest period start + computed phase",
)
async def current_cycle(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> CurrentCycleResponse:
    row = (
        await db.execute(
            select(Cycle)
            .where(Cycle.user_id == user.id)
            .order_by(Cycle.period_start_date.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "no_cycles_logged"},
        )
    phase, day = compute_phase(
        today=_today(),
        period_start_date=row.period_start_date,
        cycle_length_days=(row.cycle_length_days if row.cycle_length_days is not None else 28),
    )
    return CurrentCycleResponse(
        cycle=CycleResponse.model_validate(row),
        phase=phase,
        day=day,
    )


@router.get(
    "/history",
    response_model=list[CycleResponse],
    summary="All past cycles for the caller (newest first)",
)
async def cycles_history(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> list[Cycle]:
    rows = (
        (
            await db.execute(
                select(Cycle)
                .where(Cycle.user_id == user.id)
                .order_by(Cycle.period_start_date.desc())
            )
        )
        .scalars()
        .all()
    )
    return list(rows)


@router.patch(
    "/{cycle_id}",
    response_model=CycleResponse,
    summary="Correct or extend a logged cycle",
)
async def patch_cycle(
    cycle_id: uuid.UUID,
    payload: CycleUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Cycle:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    row = (
        await db.execute(select(Cycle).where(Cycle.id == cycle_id, Cycle.user_id == user.id))
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "cycle_not_found"},
        )
    if payload.period_start_date is not None:
        row.period_start_date = payload.period_start_date
    if payload.period_end_date is not None:
        row.period_end_date = payload.period_end_date
    if payload.cycle_length_days is not None:
        row.cycle_length_days = payload.cycle_length_days
    row.user_corrected = True
    await db.flush()
    await db.refresh(row)
    return row
