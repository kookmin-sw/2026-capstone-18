"""Pydantic response models for /me and account endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator


class CurrentUserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    supabase_user_id: uuid.UUID | None
    anon_id: uuid.UUID | None
    role: str
    display_name: str | None
    consent_raw_biosignals: bool
    consent_revoked_at: datetime | None
    deleted_at: datetime | None
    created_at: datetime


class AccountActionResponse(BaseModel):
    status: str
    deleted_at: datetime | None = None


class MeUpdate(BaseModel):
    """PATCH /api/v1/me body. Future fields land here."""

    display_name: str | None = Field(default=None, min_length=1, max_length=64)

    @field_validator("display_name")
    @classmethod
    def _strip_and_require(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if not v:
            raise ValueError("display_name must not be blank")
        return v

    def is_empty(self) -> bool:
        return len(self.model_fields_set) == 0
