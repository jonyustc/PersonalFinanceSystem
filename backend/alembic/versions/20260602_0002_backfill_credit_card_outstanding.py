"""backfill credit card outstanding from opening balance

Revision ID: 20260602_0002
Revises: 20260602_0001
Create Date: 2026-06-02 00:10:00
"""
from alembic import op


revision = "20260602_0002"
down_revision = "20260602_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE accounts
        SET
            current_outstanding = ABS(opening_balance),
            balance = 0
        WHERE lower(type) IN ('card', 'credit_card')
          AND COALESCE(current_outstanding, 0) = 0
          AND COALESCE(opening_balance, 0) <> 0;

        UPDATE credit_card_details c
        SET available_credit = GREATEST(c.credit_limit - a.current_outstanding, 0)
        FROM accounts a
        WHERE c.account_id = a.id
          AND lower(a.type) IN ('card', 'credit_card');
        """
    )


def downgrade() -> None:
    pass
