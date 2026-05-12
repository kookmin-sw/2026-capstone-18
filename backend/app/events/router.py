"""POST/GET/PATCH/DELETE /api/v1/events.

The route ownership rule: the JWT's user is *the* user. Any `user_id` field in
a request body is ignored, and any row returned must belong to the JWT's user
or the route must 404 (we don't reveal existence).
"""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, Response, status
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.models.user import User
from app.observability.metrics import events_created_total
from app.schemas.events import (
    StressEventCreate,
    StressEventFilter,
    StressEventList,
    StressEventResponse,
    StressEventUpdate,
    decode_cursor,
    encode_cursor,
)
from app.schemas.realtime import OutboundMessage
from app.services.notifications import notifier

router = APIRouter(prefix="/events", tags=["events"])


@router.post(
    "",
    response_model=StressEventResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a stress event",
)
async def create_event(
    payload: StressEventCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> StressEvent:
    if payload.category_id is not None:
        owns = (
            await db.execute(
                select(TriggerCategory.id).where(
                    TriggerCategory.id == payload.category_id,
                    TriggerCategory.user_id == user.id,
                    TriggerCategory.archived_at.is_(None),
                )
            )
        ).scalar_one_or_none()
        if owns is None:
            raise HTTPException(
                status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={"status": "error", "reason": "category_not_found"},
            )
    event = StressEvent(
        id=uuid.uuid4(),
        user_id=user.id,
        detected_at=payload.detected_at,
        model_confidence=payload.model_confidence,
        user_stress_level=payload.user_stress_level,
        mood_chips=payload.mood_chips,
        category_id=payload.category_id,
        cycle_phase=payload.cycle_phase,
        cycle_day=payload.cycle_day,
        logged=payload.logged,
        log_chips=payload.log_chips,
        log_text=payload.log_text,
        notified=payload.notified,
    )
    db.add(event)
    await db.flush()
    await db.refresh(event)
    events_created_total.inc()
    await notifier.notify_user(
        db,
        user_id=user.id,
        message=OutboundMessage(type="events.created", data={"id": str(event.id)}),
    )
    return event


@router.get(
    "",
    response_model=StressEventList,
    summary="List the caller's stress events with optional filters",
)
async def list_events(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
    start: Annotated[datetime | None, Query()] = None,
    end: Annotated[datetime | None, Query()] = None,
    logged: Annotated[bool | None, Query()] = None,
    cycle_phase: Annotated[str | None, Query()] = None,
    chip: Annotated[str | None, Query()] = None,
    cursor: Annotated[str | None, Query()] = None,
    limit: Annotated[int, Query(ge=1, le=200)] = 50,
) -> StressEventList:
    try:
        filters = StressEventFilter(
            start=start,
            end=end,
            logged=logged,
            cycle_phase=cycle_phase,
            chip=chip,
            cursor=cursor,
            limit=limit,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=422, detail={"status": "error", "reason": str(exc)}
        ) from exc

    stmt = select(StressEvent).where(StressEvent.user_id == user.id)
    if filters.start is not None:
        stmt = stmt.where(StressEvent.detected_at >= filters.start)
    if filters.end is not None:
        stmt = stmt.where(StressEvent.detected_at <= filters.end)
    if filters.logged is not None:
        stmt = stmt.where(StressEvent.logged.is_(filters.logged))
    if filters.cycle_phase is not None:
        stmt = stmt.where(StressEvent.cycle_phase == filters.cycle_phase)
    if filters.chip is not None:
        stmt = stmt.where(StressEvent.log_chips.contains([filters.chip]))

    if filters.cursor is not None:
        try:
            cur_at, cur_id = decode_cursor(filters.cursor)
        except ValueError as exc:
            raise HTTPException(
                status_code=422,
                detail={"status": "error", "reason": "invalid_cursor"},
            ) from exc
        # Keyset pagination: rows strictly older than the cursor in (detected_at, id) order.
        stmt = stmt.where(
            or_(
                StressEvent.detected_at < cur_at,
                and_(StressEvent.detected_at == cur_at, StressEvent.id < cur_id),
            )
        )

    stmt = stmt.order_by(StressEvent.detected_at.desc(), StressEvent.id.desc())
    stmt = stmt.limit(filters.limit + 1)  # +1 to detect "is there more"
    rows = (await db.execute(stmt)).scalars().all()

    has_more = len(rows) > filters.limit
    items = rows[: filters.limit]
    next_cursor = (
        encode_cursor(detected_at=items[-1].detected_at, event_id=items[-1].id)
        if has_more and items
        else None
    )
    return StressEventList(
        items=[StressEventResponse.model_validate(item) for item in items],
        next_cursor=next_cursor,
    )


@router.get(
    "/{event_id}",
    response_model=StressEventResponse,
    summary="Get a single stress event",
)
async def get_event(
    event_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> StressEvent:
    row = (
        await db.execute(
            select(StressEvent).where(
                StressEvent.id == event_id,
                StressEvent.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "event_not_found"},
        )
    return row


@router.patch(
    "/{event_id}",
    response_model=StressEventResponse,
    summary="Patch a stress event (e.g. log it after the fact)",
)
async def patch_event(
    event_id: uuid.UUID,
    payload: StressEventUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> StressEvent:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    row = (
        await db.execute(
            select(StressEvent).where(
                StressEvent.id == event_id,
                StressEvent.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "event_not_found"},
        )
    if payload.logged is not None:
        row.logged = payload.logged
    if payload.log_chips is not None:
        row.log_chips = payload.log_chips
    if payload.log_text is not None:
        row.log_text = payload.log_text
    if payload.user_stress_level is not None:
        row.user_stress_level = payload.user_stress_level
    if payload.mood_chips is not None:
        row.mood_chips = payload.mood_chips
    if "category_id" in payload.model_fields_set:
        if payload.category_id is not None:
            owns = (
                await db.execute(
                    select(TriggerCategory.id).where(
                        TriggerCategory.id == payload.category_id,
                        TriggerCategory.user_id == user.id,
                        TriggerCategory.archived_at.is_(None),
                    )
                )
            ).scalar_one_or_none()
            if owns is None:
                raise HTTPException(
                    status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
                    detail={"status": "error", "reason": "category_not_found"},
                )
        row.category_id = payload.category_id
    await db.flush()
    await db.refresh(row)
    await notifier.notify_user(
        db,
        user_id=user.id,
        message=OutboundMessage(type="events.updated", data={"id": str(row.id)}),
    )
    return row


@router.delete(
    "/{event_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Delete a stress event",
)
async def delete_event(
    event_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    row = (
        await db.execute(
            select(StressEvent).where(
                StressEvent.id == event_id,
                StressEvent.user_id == user.id,
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "event_not_found"},
        )
    await notifier.notify_user(
        db,
        user_id=user.id,
        message=OutboundMessage(type="events.deleted", data={"id": str(event_id)}),
    )
    await db.delete(row)
    await db.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
