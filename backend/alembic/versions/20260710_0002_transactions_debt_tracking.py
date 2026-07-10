"""transactions debt tracking (loans / IOU)

Adds counterparty_name + debt_type to transactions so money lent to /
borrowed from a person can be tracked and netted per counterparty.

Revision ID: 20260710_0002
Revises: 20260710_0001
Create Date: 2026-07-10 00:00:00
"""
from alembic import op


revision = "20260710_0002"
down_revision = "20260710_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE transactions
            ADD COLUMN IF NOT EXISTS counterparty_name varchar(120);
        """
    )
    op.execute(
        """
        ALTER TABLE transactions
            ADD COLUMN IF NOT EXISTS debt_type varchar(20);
        """
    )
    op.execute(
        """
        CREATE INDEX IF NOT EXISTS ix_transactions_counterparty_name
            ON transactions (counterparty_name);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS ix_transactions_counterparty_name;
        """
    )
    op.execute(
        """
        ALTER TABLE transactions
            DROP COLUMN IF EXISTS debt_type;
        """
    )
    op.execute(
        """
        ALTER TABLE transactions
            DROP COLUMN IF EXISTS counterparty_name;
        """
    )
