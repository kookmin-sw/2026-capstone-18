"""add audit_log table

Revision ID: 81190b1e74b8
Revises: 6cd3f7dbdd70
Create Date: 2026-05-07 10:44:35.630855

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


# revision identifiers, used by Alembic.
revision: str = '81190b1e74b8'
down_revision: Union[str, Sequence[str], None] = '6cd3f7dbdd70'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Audit log of privacy/deletion actions.

    No FK to users — rows must outlive the user they describe (that's the
    point of an audit log).
    """
    op.create_table(
        "audit_log",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "occurred_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("actor", sa.String(length=64), nullable=False),
        sa.Column("action", sa.String(length=64), nullable=False),
        sa.Column("target_user_id", sa.UUID(), nullable=True),
        sa.Column(
            "metadata",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'{}'::jsonb"),
            nullable=False,
        ),
        sa.PrimaryKeyConstraint("id", name="pk_audit_log"),
    )
    op.create_index("ix_audit_log_occurred_at", "audit_log", ["occurred_at"], unique=False)
    op.create_index("ix_audit_log_action_occurred_at", "audit_log", ["action", "occurred_at"], unique=False)
    op.create_index("ix_audit_log_target_user_id", "audit_log", ["target_user_id"], unique=False)


def downgrade() -> None:
    op.drop_index("ix_audit_log_target_user_id", table_name="audit_log")
    op.drop_index("ix_audit_log_action_occurred_at", table_name="audit_log")
    op.drop_index("ix_audit_log_occurred_at", table_name="audit_log")
    op.drop_table("audit_log")
