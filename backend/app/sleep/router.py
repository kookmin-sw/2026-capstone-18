"""POST/GET/PATCH/DELETE /api/v1/sleep-logs."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.sleep_log import SleepLog
from app.models.user import User
from app.schemas.sleep_logs import (
    SleepLogCreate,
    SleepLogList,
    SleepLogResponse,
    SleepLogUpdate,
)

router = APIRouter(prefix="/sleep-logs", tags=["sleep"])


@router.post(
    "",
    response_model=SleepLogResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Log last night's sleep",
)
async def create_sleep_log(
    payload: SleepLogCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    row = SleepLog(
        id=uuid.uuid4(),
        user_id=user.id,
        fell_asleep_at=payload.fell_asleep_at,
        woke_up_at=payload.woke_up_at,
        ended_on=payload.ended_on,
        rating=payload.rating,
        note=payload.note,
    )
    db.add(row)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"status": "error", "reason": "sleep_log_for_date_exists"},
        ) from exc
    await db.refresh(row)
    return row


@router.get(
    "/latest",
    responses={
        200: {"model": SleepLogResponse},
        204: {"description": "No sleep logs found"},
    },
    response_model=None,
    summary="Most recent sleep log by ended_on; 204 if none",
)
async def latest_sleep_log(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog | Response:
    row = (
        await db.execute(
            select(SleepLog)
            .where(SleepLog.user_id == user.id)
            .order_by(SleepLog.ended_on.desc(), SleepLog.created_at.desc())
            .limit(1)
        )
    ).scalar_one_or_none()
    if row is None:
        return Response(status_code=status.HTTP_204_NO_CONTENT)
    return row


@router.get(
    "",
    response_model=SleepLogList,
    summary="List the caller's sleep logs (newest first)",
)
async def list_sleep_logs(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    start: Annotated[datetime | None, Query()] = None,
    end: Annotated[datetime | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> SleepLogList:
    stmt = select(SleepLog).where(SleepLog.user_id == user.id)
    if start is not None:
        stmt = stmt.where(SleepLog.fell_asleep_at >= start)
    if end is not None:
        stmt = stmt.where(SleepLog.woke_up_at <= end)
    stmt = stmt.order_by(SleepLog.ended_on.desc()).limit(limit)
    rows = (await db.execute(stmt)).scalars().all()
    return SleepLogList(items=[SleepLogResponse.model_validate(r) for r in rows])


async def _load(db: AsyncSession, user_id: uuid.UUID, log_id: uuid.UUID) -> SleepLog:
    row = (
        await db.execute(select(SleepLog).where(SleepLog.id == log_id, SleepLog.user_id == user_id))
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "sleep_log_not_found"},
        )
    return row


@router.get("/{log_id}", response_model=SleepLogResponse)
async def get_sleep_log(
    log_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    return await _load(db, user.id, log_id)


@router.patch(
    "/{log_id}",
    response_model=SleepLogResponse,
    summary="Edit the rating, note, or window of a sleep log",
)
async def patch_sleep_log(
    log_id: uuid.UUID,
    payload: SleepLogUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> SleepLog:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    row = await _load(db, user.id, log_id)
    if payload.fell_asleep_at is not None:
        row.fell_asleep_at = payload.fell_asleep_at
    if payload.woke_up_at is not None:
        row.woke_up_at = payload.woke_up_at
    if payload.rating is not None:
        row.rating = payload.rating
    if "note" in payload.model_fields_set:
        row.note = payload.note
    try:
        await db.flush()
    except IntegrityError as exc:
        # SleepLogUpdate intentionally does not expose `ended_on`. That means the
        # `uq_sleep_logs_user_ended` unique index can never fire on PATCH — the
        # only IntegrityError reachable here is a CHECK violation (window order
        # or 60-1440 minute range). If `ended_on` is ever added to the update
        # schema, this handler must inspect `exc.orig.pgcode` to distinguish
        # uniqueness (23505) from check (23514).
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "sleep_window_invalid"},
        ) from exc
    await db.refresh(row)
    return row


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_sleep_log(
    log_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    row = await _load(db, user.id, log_id)
    await db.delete(row)
    await db.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
