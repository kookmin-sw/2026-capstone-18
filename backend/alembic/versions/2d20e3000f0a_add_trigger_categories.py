"""add trigger categories

Revision ID: 2d20e3000f0a
Revises: 6de161daa1f1
Create Date: 2026-05-07 21:47:56.358696

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = "2d20e3000f0a"
down_revision: Union[str, Sequence[str], None] = "6de161daa1f1"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add trigger_categories + category_id FK on stress_events."""
    op.create_table(
        "trigger_categories",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("name", sa.String(length=64), nullable=False),
        sa.Column("color", sa.String(length=7), nullable=False),
        sa.Column("sort_order", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("archived_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"],
            ondelete="CASCADE",
            name="fk_trigger_categories_user_id",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_trigger_categories"),
    )
    op.create_index(
        "ix_trigger_categories_user_id",
        "trigger_categories",
        ["user_id"],
    )
    # One active category per name, per user. Archived rows are excluded so users
    # can re-create a previously deleted category.
    op.create_index(
        "uq_trigger_categories_user_name_active",
        "trigger_categories",
        ["user_id", sa.text("lower(name)")],
        unique=True,
        postgresql_where=sa.text("archived_at IS NULL"),
    )
    op.add_column(
        "stress_events",
        sa.Column("category_id", sa.UUID(), nullable=True),
    )
    op.create_foreign_key(
        "fk_stress_events_category_id",
        "stress_events",
        "trigger_categories",
        ["category_id"],
        ["id"],
        ondelete="SET NULL",
    )
    op.create_index(
        "ix_stress_events_category_id",
        "stress_events",
        ["category_id"],
    )


def downgrade() -> None:
    op.drop_index("ix_stress_events_category_id", table_name="stress_events")
    op.drop_constraint(
        "fk_stress_events_category_id", "stress_events", type_="foreignkey"
    )
    op.drop_column("stress_events", "category_id")
    op.drop_index(
        "uq_trigger_categories_user_name_active", table_name="trigger_categories"
    )
    op.drop_index(
        "ix_trigger_categories_user_id", table_name="trigger_categories"
    )
    op.drop_table("trigger_categories")
