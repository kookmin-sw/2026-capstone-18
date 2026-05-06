"""add websocket connections fcm tokens sync

Revision ID: 6cd3f7dbdd70
Revises: adbd022fc5c1
Create Date: 2026-05-06 20:57:32.109624

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6cd3f7dbdd70'
down_revision: Union[str, Sequence[str], None] = 'adbd022fc5c1'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    op.create_table(
        "websocket_connections",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("task_id", sa.String(length=128), nullable=False),
        sa.Column(
            "connected_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index("ix_websocket_connections_user_id", "websocket_connections", ["user_id"])
    op.create_index("ix_websocket_connections_task_id", "websocket_connections", ["task_id"])
    op.create_index(
        "ix_websocket_connections_last_seen_at",
        "websocket_connections",
        ["last_seen_at"],
    )
    op.create_table(
        "fcm_tokens",
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("token", sa.String(length=512), nullable=False),
        sa.Column("platform", sa.String(length=16), nullable=False),
        sa.Column(
            "registered_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column(
            "last_seen_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("user_id", "token", name="pk_fcm_tokens"),
    )
    op.create_index("ix_fcm_tokens_user_id", "fcm_tokens", ["user_id"])


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index("ix_fcm_tokens_user_id", table_name="fcm_tokens")
    op.drop_table("fcm_tokens")
    op.drop_index("ix_websocket_connections_last_seen_at", table_name="websocket_connections")
    op.drop_index("ix_websocket_connections_task_id", table_name="websocket_connections")
    op.drop_index("ix_websocket_connections_user_id", table_name="websocket_connections")
    op.drop_table("websocket_connections")
