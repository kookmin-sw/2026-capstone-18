"""Tests for app.services.audit.record_audit."""

from __future__ import annotations

import uuid

import pytest
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.audit_log import AuditLog
from app.services.audit import record_audit


@pytest.mark.asyncio
async def test_record_audit_persists_row(db_session: AsyncSession) -> None:
    user_id = uuid.uuid4()
    await record_audit(
        db_session,
        actor="system:purge_accounts",
        action="hard_delete_user",
        target_user_id=user_id,
        metadata={"s3_objects_deleted": 5},
    )
    await db_session.flush()

    rows = (await db_session.execute(select(AuditLog))).scalars().all()
    assert len(rows) == 1
    assert rows[0].actor == "system:purge_accounts"
    assert rows[0].action == "hard_delete_user"
    assert rows[0].target_user_id == user_id
    assert rows[0].metadata_ == {"s3_objects_deleted": 5}


@pytest.mark.asyncio
async def test_record_audit_metadata_optional(db_session: AsyncSession) -> None:
    await record_audit(
        db_session,
        actor="system:test",
        action="noop",
    )
    await db_session.flush()
    rows = (await db_session.execute(select(AuditLog))).scalars().all()
    assert len(rows) == 1
    assert rows[0].metadata_ == {}
    assert rows[0].target_user_id is None
