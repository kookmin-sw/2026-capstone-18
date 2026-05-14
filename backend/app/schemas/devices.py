"""Pydantic schemas for /api/v1/devices."""

from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class FcmTokenRegister(BaseModel):
    token: str = Field(min_length=1, max_length=512)
    platform: Literal["android", "ios"]


class FcmTokenUnregister(BaseModel):
    """Body for DELETE /devices/fcm-token. Token-only; platform is implicit."""

    token: str = Field(min_length=1, max_length=512)


class FcmTokenResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    token: str
    platform: str
    registered_at: datetime
    last_seen_at: datetime
