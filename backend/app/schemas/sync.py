"""Pydantic schemas for /api/v1/sync."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field

# 256 MiB cap.
MAX_BLOB_BYTES = 256 * 1024 * 1024


class SyncUploadRequest(BaseModel):
    kind: Literal["backup"]
    byte_size: int = Field(gt=0, le=MAX_BLOB_BYTES)
    content_hash: str = Field(min_length=1, max_length=128)


class SyncUploadResponse(BaseModel):
    blob_id: uuid.UUID
    s3_object_key: str
    presigned_put_url: str
    expires_in: int


class SyncDownloadResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    blob_id: uuid.UUID
    s3_object_key: str
    presigned_get_url: str
    byte_size: int
    created_at: datetime


SignalType = Literal["hrv", "ppg", "eda", "temp", "accel"]


class BiosignalUploadRequest(BaseModel):
    signal_type: SignalType
    recorded_at: datetime
    byte_size: int = Field(gt=0, le=MAX_BLOB_BYTES)
    content_hash: str = Field(min_length=1, max_length=128)


class BiosignalUploadResponse(BaseModel):
    upload_id: uuid.UUID
    s3_object_key: str
    presigned_put_url: str
    expires_in: int
    expires_at: datetime
