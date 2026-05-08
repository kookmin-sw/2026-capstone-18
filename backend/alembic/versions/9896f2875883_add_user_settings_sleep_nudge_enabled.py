"""add user_settings sleep_nudge_enabled

Revision ID: 9896f2875883
Revises: abd7e990abd2
Create Date: 2026-05-08 12:41:46.022140

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = '9896f2875883'
down_revision: Union[str, Sequence[str], None] = 'abd7e990abd2'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add sleep_nudge_enabled toggle to user_settings (default true)."""
    op.add_column(
        "user_settings",
        sa.Column(
            "sleep_nudge_enabled",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("true"),
        ),
    )


def downgrade() -> None:
    op.drop_column("user_settings", "sleep_nudge_enabled")
