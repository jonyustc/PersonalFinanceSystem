"""expand account type constraint

Revision ID: 20260602_0001
Revises: 20260601_0001
Create Date: 2026-06-02 00:00:00
"""
from alembic import op


revision = "20260602_0001"
down_revision = "20260601_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE accounts
            DROP CONSTRAINT IF EXISTS accounts_type_check;

        ALTER TABLE accounts
            ADD CONSTRAINT accounts_type_check
            CHECK (lower(type) IN (
                'cash',
                'bank',
                'card',
                'mobile_banking',
                'debit_card',
                'credit_card'
            ));
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE accounts
            DROP CONSTRAINT IF EXISTS accounts_type_check;

        ALTER TABLE accounts
            ADD CONSTRAINT accounts_type_check
            CHECK (lower(type) IN ('cash', 'bank', 'card'));
        """
    )
