"""Tests for the User model — placeholder fields only in Sprint 1."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime

import pytest
from sqlalchemy import select

from app.db.session import AsyncSessionLocal
from app.models.user import User


@pytest.mark.asyncio
async def test_create_user_persists_to_db() -> None:
    user = User()
    async with AsyncSessionLocal() as session:
        session.add(user)
        await session.commit()
        assert user.id is not None
        assert isinstance(user.id, uuid.UUID)
        assert user.created_at is not None
        assert isinstance(user.created_at, datetime)


@pytest.mark.asyncio
async def test_query_user_round_trip() -> None:
    user = User()
    async with AsyncSessionLocal() as session:
        session.add(user)
        await session.commit()
        original_id = user.id

    # New session — proves the row really hit the DB
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(User).where(User.id == original_id))
        fetched = result.scalar_one()
        assert fetched.id == original_id
        # created_at should be timezone-aware and recent
        assert fetched.created_at.tzinfo is not None
        delta = datetime.now(UTC) - fetched.created_at
        assert delta.total_seconds() < 60
