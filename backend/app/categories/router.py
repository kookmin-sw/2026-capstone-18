"""GET / POST / PATCH / DELETE /api/v1/categories."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.stress_event import StressEvent
from app.models.trigger_category import TriggerCategory
from app.models.user import User
from app.schemas.trigger_categories import (
    TriggerCategoryCreate,
    TriggerCategoryList,
    TriggerCategoryResponse,
    TriggerCategoryUpdate,
)

router = APIRouter(prefix="/categories", tags=["categories"])


def _to_response(row: TriggerCategory, event_count: int) -> TriggerCategoryResponse:
    payload = TriggerCategoryResponse.model_validate(row)
    payload.event_count = event_count
    return payload


@router.post(
    "",
    response_model=TriggerCategoryResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Create a trigger category",
)
async def create_category(
    payload: TriggerCategoryCreate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TriggerCategoryResponse:
    sort_order = payload.sort_order
    if sort_order is None:
        max_order = (
            await db.execute(
                select(func.coalesce(func.max(TriggerCategory.sort_order), -1)).where(
                    TriggerCategory.user_id == user.id,
                    TriggerCategory.archived_at.is_(None),
                )
            )
        ).scalar_one()
        # Note: this is racy under concurrent POSTs (two callers can read max=N
        # and both write N+1). Acceptable for personal-app traffic; revisit if
        # we ever see a sort_order collision in production.
        sort_order = int(max_order) + 1

    row = TriggerCategory(
        id=uuid.uuid4(),
        user_id=user.id,
        name=payload.name,
        color=payload.color,
        sort_order=sort_order,
    )
    db.add(row)
    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"status": "error", "reason": "category_name_already_exists"},
        ) from exc
    await db.refresh(row)
    return _to_response(row, event_count=0)


@router.get(
    "",
    response_model=TriggerCategoryList,
    summary="List the caller's trigger categories with event counts",
)
async def list_categories(
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TriggerCategoryList:
    counts_subq = (
        select(
            StressEvent.category_id,
            func.count(StressEvent.id).label("event_count"),
        )
        .where(StressEvent.user_id == user.id)
        .group_by(StressEvent.category_id)
        .subquery()
    )

    stmt = (
        select(
            TriggerCategory,
            func.coalesce(counts_subq.c.event_count, 0).label("event_count"),
        )
        .join(
            counts_subq,
            counts_subq.c.category_id == TriggerCategory.id,
            isouter=True,
        )
        .where(
            TriggerCategory.user_id == user.id,
            TriggerCategory.archived_at.is_(None),
        )
        .order_by(TriggerCategory.sort_order, TriggerCategory.created_at)
    )

    rows = (await db.execute(stmt)).all()
    items = [_to_response(row, int(count)) for row, count in rows]
    return TriggerCategoryList(items=items)


@router.patch(
    "/{category_id}",
    response_model=TriggerCategoryResponse,
    summary="Rename / recolor / reorder a trigger category",
)
async def patch_category(
    category_id: uuid.UUID,
    payload: TriggerCategoryUpdate,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> TriggerCategoryResponse:
    if payload.is_empty():
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail={"status": "error", "reason": "empty_patch_body"},
        )
    counts_subq = (
        select(
            StressEvent.category_id,
            func.count(StressEvent.id).label("event_count"),
        )
        .where(StressEvent.user_id == user.id)
        .group_by(StressEvent.category_id)
        .subquery()
    )
    fetched = (
        await db.execute(
            select(
                TriggerCategory,
                func.coalesce(counts_subq.c.event_count, 0).label("event_count"),
            )
            .join(
                counts_subq,
                counts_subq.c.category_id == TriggerCategory.id,
                isouter=True,
            )
            .where(
                TriggerCategory.id == category_id,
                TriggerCategory.user_id == user.id,
                TriggerCategory.archived_at.is_(None),
            )
        )
    ).one_or_none()
    if fetched is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "category_not_found"},
        )
    row, event_count = fetched
    if payload.name is not None:
        row.name = payload.name
    if payload.color is not None:
        row.color = payload.color
    if payload.sort_order is not None:
        row.sort_order = payload.sort_order

    try:
        await db.flush()
    except IntegrityError as exc:
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail={"status": "error", "reason": "category_name_already_exists"},
        ) from exc
    await db.refresh(row)
    return _to_response(row, int(event_count))


@router.delete(
    "/{category_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="Soft-archive a trigger category and clear it from events",
)
async def delete_category(
    category_id: uuid.UUID,
    user: Annotated[User, Depends(get_current_user)],
    db: Annotated[AsyncSession, Depends(get_db)],
) -> Response:
    row = (
        await db.execute(
            select(TriggerCategory).where(
                TriggerCategory.id == category_id,
                TriggerCategory.user_id == user.id,
                TriggerCategory.archived_at.is_(None),
            )
        )
    ).scalar_one_or_none()
    if row is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail={"status": "error", "reason": "category_not_found"},
        )
    row.archived_at = datetime.now(tz=UTC)
    events = (
        (
            await db.execute(
                select(StressEvent).where(
                    StressEvent.user_id == user.id,
                    StressEvent.category_id == row.id,
                )
            )
        )
        .scalars()
        .all()
    )
    for ev in events:
        ev.category_id = None
    await db.flush()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
