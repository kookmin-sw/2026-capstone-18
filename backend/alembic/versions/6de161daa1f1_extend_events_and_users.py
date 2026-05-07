"""extend events and users

Revision ID: 6de161daa1f1
Revises: 81190b1e74b8
Create Date: 2026-05-07 19:13:11.785025

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6de161daa1f1'
down_revision: Union[str, Sequence[str], None] = '81190b1e74b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add user-rated stress slider, mood chips, and display name."""
    op.add_column(
        "stress_events",
        sa.Column("user_stress_level", sa.Integer(), nullable=True),
    )
    op.create_check_constraint(
        "ck_stress_events_user_stress_level_range",
        "stress_events",
        sa.text("user_stress_level IS NULL OR (user_stress_level BETWEEN 0 AND 100)"),
    )
    op.add_column(
        "stress_events",
        sa.Column("mood_chips", sa.ARRAY(sa.String()), nullable=True),
    )
    op.add_column(
        "users",
        sa.Column("display_name", sa.String(length=64), nullable=True),
    )


def downgrade() -> None:
    """Reverse — drop in opposite order."""
    op.drop_column("users", "display_name")
    op.drop_column("stress_events", "mood_chips")
    op.drop_constraint(
        "ck_stress_events_user_stress_level_range",
        "stress_events",
        type_="check",
    )
    op.drop_column("stress_events", "user_stress_level")
