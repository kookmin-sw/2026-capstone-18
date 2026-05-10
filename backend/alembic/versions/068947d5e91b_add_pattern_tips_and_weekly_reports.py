"""add_pattern_tips_and_weekly_reports

Revision ID: 068947d5e91b
Revises: 9896f2875883
Create Date: 2026-05-10

"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision = "068947d5e91b"
down_revision = "9896f2875883"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "pattern_tips",
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
        sa.Column("pattern_key", sa.String(64), nullable=False),
        sa.Column("tip_text", sa.Text(), nullable=False),
        sa.Column(
            "generated_at",
            sa.DateTime(timezone=True),
            nullable=False,
            server_default=sa.text("now()"),
        ),
        sa.UniqueConstraint("user_id", "pattern_key", name="pattern_tips_user_key_unique"),
    )
    op.create_index(
        "ix_pattern_tips_user_generated",
        "pattern_tips",
        ["user_id", "generated_at"],
        unique=False,
    )

    op.create_table(
        "weekly_reports",
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
        sa.Column("week_start", sa.Date(), nullable=False),
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
        sa.UniqueConstraint("user_id", "week_start", name="weekly_reports_user_week_unique"),
    )
    op.create_index(
        "ix_weekly_reports_user_week",
        "weekly_reports",
        ["user_id", "week_start"],
        unique=False,
    )


def downgrade() -> None:
    op.drop_index("ix_weekly_reports_user_week", table_name="weekly_reports")
    op.drop_table("weekly_reports")
    op.drop_index("ix_pattern_tips_user_generated", table_name="pattern_tips")
    op.drop_table("pattern_tips")
