"""add cycles is_period_ongoing

Revision ID: 4a7b2c918f3e
Revises: ab3301b1cf68
Create Date: 2026-05-13

"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "4a7b2c918f3e"
down_revision = "ab3301b1cf68"
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Add is_period_ongoing flag to cycles (default false)."""
    op.add_column(
        "cycles",
        sa.Column(
            "is_period_ongoing",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
    )


def downgrade() -> None:
    op.drop_column("cycles", "is_period_ongoing")
