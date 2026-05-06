"""Pydantic schemas for /api/v1/consent."""

from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel


class ConsentResponse(BaseModel):
    """Snapshot of every consent toggle the user controls."""

    consent_raw_biosignals: bool
    consent_revoked_at: datetime | None
    consent_audit_logging: bool


class ConsentUpdate(BaseModel):
    """Each field is optional — `None` means "leave unchanged"."""

    consent_raw_biosignals: bool | None = None
    consent_audit_logging: bool | None = None

    def is_empty(self) -> bool:
        return all(v is None for v in self.model_dump().values())
