"""add stress_events and cycles tables

Revision ID: adbd022fc5c1
Revises: 7bdacbea490e
Create Date: 2026-05-06 14:26:35.562870

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'adbd022fc5c1'
down_revision: Union[str, Sequence[str], None] = '7bdacbea490e'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "stress_events",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("detected_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("model_confidence", sa.Float(), nullable=True),
        sa.Column("cycle_phase", sa.String(length=16), nullable=True),
        sa.Column("cycle_day", sa.Integer(), nullable=True),
        sa.Column("logged", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("log_chips", sa.ARRAY(sa.String()), nullable=True),
        sa.Column("log_text", sa.Text(), nullable=True),
        sa.Column("notified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("user_response", sa.String(length=16), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", "detected_at", name="pk_stress_events"),
    )
    op.create_index("ix_stress_events_id", "stress_events", ["id"], unique=False)
    op.create_index(
        "ix_stress_events_user_detected",
        "stress_events",
        ["user_id", "detected_at"],
        unique=False,
    )
    # Convert to TimescaleDB hypertable. `if_not_exists => TRUE` makes the
    # migration idempotent in case someone re-runs it after a partial failure.
    op.execute(
        "SELECT create_hypertable('stress_events', 'detected_at', if_not_exists => TRUE)"
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_stress_events_user_detected", table_name="stress_events")
    op.drop_index("ix_stress_events_id", table_name="stress_events")
    op.drop_table("stress_events")
