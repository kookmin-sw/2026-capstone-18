"""Pydantic response models for /me and account endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict


class CurrentUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    supabase_user_id: uuid.UUID | None
    anon_id: uuid.UUID | None
    role: str
    consent_raw_biosignals: bool
    consent_revoked_at: datetime | None
    deleted_at: datetime | None
    created_at: datetime


class AccountActionResponse(BaseModel):
    status: str
    deleted_at: datetime | None = None
