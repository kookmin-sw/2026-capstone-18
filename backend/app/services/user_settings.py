"""User settings creation helper.

Default values come from the spec / `UserSettings.__table_args__` server defaults.
We instantiate the model with no overrides so SQLAlchemy applies the server
defaults on flush. Calling this helper twice in the same request is a no-op
because we look up the existing row first.
"""

from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.user import User
from app.models.user_settings import UserSettings


async def ensure_user_settings(db: AsyncSession, user: User) -> UserSettings:
    existing = (
        await db.execute(select(UserSettings).where(UserSettings.user_id == user.id))
    ).scalar_one_or_none()
    if existing is not None:
        return existing
    settings = UserSettings(user_id=user.id)
    db.add(settings)
    await db.flush()
    await db.refresh(settings)
    return settings
