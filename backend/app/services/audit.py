"""record_audit — single helper for writing AuditLog rows.

Callers pass an existing AsyncSession; commit is the caller's responsibility.
This keeps audit writes inside the same transaction as the action they describe,
so we never log a delete that didn't happen.
"""

from __future__ import annotations

import uuid
from typing import Any

from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditLog


async def record_audit(
    db: AsyncSession,
    *,
    actor: str,
    action: str,
    target_user_id: uuid.UUID | None = None,
    metadata: dict[str, Any] | None = None,
) -> AuditLog:
    """Insert one audit_log row. Caller commits."""
    row = AuditLog(
        actor=actor,
        action=action,
        target_user_id=target_user_id,
        metadata_=metadata or {},
    )
    db.add(row)
    return row
