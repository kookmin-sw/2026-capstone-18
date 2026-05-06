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
        sa.CheckConstraint(
            "platform IN ('android', 'ios')",
            name="ck_fcm_tokens_platform",
        ),
        sa.PrimaryKeyConstraint("user_id", "token", name="pk_fcm_tokens"),
    )
    op.create_index("ix_fcm_tokens_user_id", "fcm_tokens", ["user_id"])
    op.create_table(
        "sync_blobs",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("s3_object_key", sa.String(length=512), nullable=False),
        sa.Column("kind", sa.String(length=32), nullable=False),
        sa.Column("byte_size", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_sync_blobs_user_kind_created",
        "sync_blobs",
        ["user_id", "kind", "created_at"],
    )
    op.create_table(
        "raw_biosignal_uploads",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column("user_id", sa.UUID(), nullable=False),
        sa.Column("s3_object_key", sa.String(length=512), nullable=False),
        sa.Column("signal_type", sa.String(length=16), nullable=False),
        sa.Column("recorded_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "uploaded_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("now()"),
            nullable=False,
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id", "recorded_at", name="pk_raw_biosignal_uploads"),
    )
    op.create_index(
        "ix_raw_biosignal_uploads_id", "raw_biosignal_uploads", ["id"], unique=False
    )
    op.create_index(
        "ix_raw_biosignal_uploads_user_recorded",
        "raw_biosignal_uploads",
        ["user_id", "recorded_at"],
        unique=False,
    )
    op.execute(
        "SELECT create_hypertable('raw_biosignal_uploads', 'recorded_at', if_not_exists => TRUE)"
    )


def downgrade() -> None:
    """Downgrade schema."""
    op.drop_index(
        "ix_raw_biosignal_uploads_user_recorded", table_name="raw_biosignal_uploads"
    )
    op.drop_index("ix_raw_biosignal_uploads_id", table_name="raw_biosignal_uploads")
    op.drop_table("raw_biosignal_uploads")
    op.drop_index("ix_sync_blobs_user_kind_created", table_name="sync_blobs")
    op.drop_table("sync_blobs")
    op.drop_constraint("ck_fcm_tokens_platform", "fcm_tokens", type_="check")
    op.drop_index("ix_fcm_tokens_user_id", table_name="fcm_tokens")
    op.drop_table("fcm_tokens")
    op.drop_index("ix_websocket_connections_last_seen_at", table_name="websocket_connections")
    op.drop_index("ix_websocket_connections_task_id", table_name="websocket_connections")
    op.drop_index("ix_websocket_connections_user_id", table_name="websocket_connections")
    op.drop_table("websocket_connections")
