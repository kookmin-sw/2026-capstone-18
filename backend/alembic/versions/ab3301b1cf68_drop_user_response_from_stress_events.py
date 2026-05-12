"""drop_user_response_from_stress_events

Revision ID: ab3301b1cf68
Revises: b1f8e3a0c742
Create Date: 2026-05-12

"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op


revision = "ab3301b1cf68"
down_revision = "b1f8e3a0c742"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.drop_column("stress_events", "user_response")


def downgrade() -> None:
    op.add_column(
        "stress_events",
        sa.Column("user_response", sa.String(length=16), nullable=True),
    )
