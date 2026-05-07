"""AuditLog ORM model basics."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditLog


@pytest.mark.asyncio
async def test_audit_log_insert_and_read(db_session: AsyncSession) -> None:
    target = uuid.uuid4()
    row = AuditLog(
        actor="system:purge_accounts",
        action="hard_delete_user",
        target_user_id=target,
        metadata_={"s3_objects_deleted": 3},
    )
    db_session.add(row)
    await db_session.flush()

    found = (await db_session.execute(select(AuditLog).where(AuditLog.id == row.id))).scalar_one()
    assert found.actor == "system:purge_accounts"
    assert found.action == "hard_delete_user"
    assert found.target_user_id == target
    assert found.metadata_ == {"s3_objects_deleted": 3}
    assert found.occurred_at is not None


@pytest.mark.asyncio
async def test_audit_log_target_user_id_optional(db_session: AsyncSession) -> None:
    """target_user_id is nullable — used for system-level events with no user target."""
    row = AuditLog(actor="system:scheduler", action="schedule_invoked")
    db_session.add(row)
    await db_session.flush()
    assert row.target_user_id is None
    assert row.metadata_ == {}
