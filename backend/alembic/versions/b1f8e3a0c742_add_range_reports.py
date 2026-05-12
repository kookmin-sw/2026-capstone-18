"""add_range_reports

Revision ID: b1f8e3a0c742
Revises: 068947d5e91b
Create Date: 2026-05-12

"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision = "b1f8e3a0c742"
down_revision = "068947d5e91b"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "range_reports",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("period_start", sa.Date(), nullable=False),
        sa.Column("period_end", sa.Date(), nullable=False),
        sa.Column("headline", sa.Text(), nullable=False),
        sa.Column("body_md", sa.Text(), nullable=False),
        sa.Column(
            "takeaways",
            postgresql.JSONB(astext_type=sa.Text()),
            nullable=False,
            server_default=sa.text("'[]'::jsonb"),
        ),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint(
            "user_id",
            "period_start",
            "period_end",
            name="range_reports_user_period_unique",
        ),
    )
    op.create_index(
        "ix_range_reports_user_period",
        "range_reports",
        ["user_id", "period_start", "period_end"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_range_reports_user_period", table_name="range_reports")
    op.drop_table("range_reports")
