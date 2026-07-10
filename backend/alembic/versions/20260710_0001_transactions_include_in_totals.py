"""transactions include_in_totals flag

Adds a boolean flag to transactions. When false, the transaction still moves
account balances normally but is excluded from spending/income aggregations
(analytics, dashboard, reports, budget "spent" amounts).

Revision ID: 20260710_0001
Revises: 20260620_0001
Create Date: 2026-07-10 00:00:00
"""
from alembic import op


revision = "20260710_0001"
down_revision = "20260620_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE transactions
            ADD COLUMN IF NOT EXISTS include_in_totals boolean NOT NULL DEFAULT true;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE transactions
            DROP COLUMN IF EXISTS include_in_totals;
        """
    )
