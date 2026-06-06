"""portfolio dividend record date

Revision ID: 20260606_0001
Revises: 20260604_0001
Create Date: 2026-06-06 17:30:00
"""
from alembic import op


revision = "20260606_0001"
down_revision = "20260604_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE portfolio_transactions
            ADD COLUMN IF NOT EXISTS record_date date;
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_record_date
            ON portfolio_transactions(record_date);

        ALTER TABLE dividends
            ADD COLUMN IF NOT EXISTS record_date date;
        CREATE INDEX IF NOT EXISTS ix_dividends_record_date
            ON dividends(record_date);
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_dividends_record_date;")
    op.execute("ALTER TABLE dividends DROP COLUMN IF EXISTS record_date;")
    op.execute("DROP INDEX IF EXISTS ix_portfolio_transactions_record_date;")
    op.execute("ALTER TABLE portfolio_transactions DROP COLUMN IF EXISTS record_date;")
