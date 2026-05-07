"""GET / POST /api/v1/categories."""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status
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
