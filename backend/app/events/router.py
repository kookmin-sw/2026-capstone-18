"""POST/GET/PATCH/DELETE /api/v1/events.

The route ownership rule: the JWT's user is *the* user. Any `user_id` field in
a request body is ignored, and any row returned must belong to the JWT's user
or the route must 404 (we don't reveal existence).
"""

from __future__ import annotations

import uuid
from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth.dependencies import get_current_user
from app.db.dependencies import get_db
from app.models.stress_event import StressEvent
from app.models.user import User
from app.schemas.events import StressEventCreate, StressEventResponse

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
    event = StressEvent(
        id=uuid.uuid4(),
        user_id=user.id,
        detected_at=payload.detected_at,
        model_confidence=payload.model_confidence,
        cycle_phase=payload.cycle_phase,
        cycle_day=payload.cycle_day,
        logged=payload.logged,
        log_chips=payload.log_chips,
        log_text=payload.log_text,
        notified=payload.notified,
        user_response=payload.user_response,
    )
    db.add(event)
    await db.flush()
    await db.refresh(event)
    return event
