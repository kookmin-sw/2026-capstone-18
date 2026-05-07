"""Wire schemas for /api/v1/categories."""

from __future__ import annotations

import re
import uuid
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

_HEX_COLOR = re.compile(r"^#[0-9A-Fa-f]{6}$")


class TriggerCategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=64)
    color: str
    sort_order: int | None = None

    @field_validator("name")
    @classmethod
    def _strip_and_require(cls, v: str) -> str:
        v = v.strip()
        if not v:
            raise ValueError("name must not be blank")
        return v

    @field_validator("color")
    @classmethod
    def _hex_only(cls, v: str) -> str:
        if not _HEX_COLOR.match(v):
            raise ValueError("color must be a 7-char hex like #RRGGBB")
        return v.upper()


class TriggerCategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=64)
    color: str | None = None
    sort_order: int | None = None

    @field_validator("name")
    @classmethod
    def _strip_and_require(cls, v: str | None) -> str | None:
        if v is None:
            return None
        v = v.strip()
        if not v:
            raise ValueError("name must not be blank")
        return v

    @field_validator("color")
    @classmethod
    def _hex_only(cls, v: str | None) -> str | None:
        if v is None:
            return None
        if not _HEX_COLOR.match(v):
            raise ValueError("color must be a 7-char hex like #RRGGBB")
        return v.upper()

    def is_empty(self) -> bool:
        return all(v is None for v in self.model_dump().values())


class TriggerCategoryResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    name: str
    color: str
    sort_order: int
    archived_at: datetime | None
    created_at: datetime
    event_count: int = 0


class TriggerCategoryList(BaseModel):
    items: list[TriggerCategoryResponse]
