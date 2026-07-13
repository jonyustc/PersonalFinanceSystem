"""sync tombstones

Adds a sync_tombstones table so offline clients can replay hard deletions.
Deletes across the app stay hard deletes; the delete path drops one tombstone
row here, and GET /sync/changes?since=<ts> returns tombstones with
deleted_at > since so the client removes the matching local mirror rows.

Revision ID: 20260712_0001
Revises: 20260710_0002
Create Date: 2026-07-12 00:00:00
"""
from alembic import op


revision = "20260712_0001"
down_revision = "20260710_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS sync_tombstones (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            resource varchar(40) NOT NULL,
            entity_id uuid NOT NULL,
            deleted_at timestamptz NOT NULL DEFAULT now()
        );
        """
    )
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_sync_tombstones_user_id
            ON sync_tombstones (user_id);
        """
    )
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_sync_tombstones_deleted_at
            ON sync_tombstones (deleted_at);
        """
    )
    # A resource+entity is deleted at most once; keep the feed compact and make
    # tombstone recording idempotent under retries.
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_tombstones_user_resource_entity
            ON sync_tombstones (user_id, resource, entity_id);
        """
    )


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS sync_tombstones;")
