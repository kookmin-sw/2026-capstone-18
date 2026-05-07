"""add sleep logs

Revision ID: abd7e990abd2
Revises: 2d20e3000f0a
Create Date: 2026-05-07 22:32:01.486141

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


revision: str = 'abd7e990abd2'
down_revision: Union[str, Sequence[str], None] = '2d20e3000f0a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create sleep_logs table with generated total_minutes column."""
    op.create_table(
        "sleep_logs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("fell_asleep_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("woke_up_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_on", sa.Date(), nullable=False),
        sa.Column(
            "total_minutes",
            sa.Integer(),
            sa.Computed(
                "(EXTRACT(EPOCH FROM (woke_up_at - fell_asleep_at)) / 60)::int",
                persisted=True,
            ),
            nullable=False,
        ),
        sa.Column("rating", sa.String(length=16), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"],
            ondelete="CASCADE",
            name="fk_sleep_logs_user_id",
        ),
        sa.PrimaryKeyConstraint("id", name="pk_sleep_logs"),
    )
    op.create_index(
        "uq_sleep_logs_user_ended",
        "sleep_logs",
        ["user_id", "ended_on"],
        unique=True,
    )
    op.create_check_constraint(
        "ck_sleep_logs_window_positive",
        "sleep_logs",
        sa.text("woke_up_at > fell_asleep_at"),
    )
    op.create_check_constraint(
        "ck_sleep_logs_total_minutes_range",
        "sleep_logs",
        sa.text("total_minutes BETWEEN 60 AND 1440"),
    )
    op.create_check_constraint(
        "ck_sleep_logs_rating_enum",
        "sleep_logs",
        sa.text(
            "rating IN ('very_poor','poor','okay','good','great')"
        ),
    )


def downgrade() -> None:
    op.drop_constraint("ck_sleep_logs_rating_enum", "sleep_logs", type_="check")
    op.drop_constraint("ck_sleep_logs_total_minutes_range", "sleep_logs", type_="check")
    op.drop_constraint("ck_sleep_logs_window_positive", "sleep_logs", type_="check")
    op.drop_index("uq_sleep_logs_user_ended", table_name="sleep_logs")
    op.drop_table("sleep_logs")
