"""treat credit card opening balance as available limit

Revision ID: 20260602_0003
Revises: 20260602_0002
Create Date: 2026-06-02 00:20:00
"""
from alembic import op


revision = "20260602_0003"
down_revision = "20260602_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        UPDATE accounts
        SET
            current_outstanding = GREATEST(COALESCE(credit_limit, 0) - COALESCE(opening_balance, 0), 0),
            balance = 0
        WHERE lower(type) IN ('card', 'credit_card')
          AND credit_limit IS NOT NULL
          AND COALESCE(opening_balance, 0) > 0
          AND COALESCE(current_outstanding, 0) = ABS(COALESCE(opening_balance, 0));

        UPDATE credit_card_details c
        SET available_credit = GREATEST(c.credit_limit - a.current_outstanding, 0)
        FROM accounts a
        WHERE c.account_id = a.id
          AND lower(a.type) IN ('card', 'credit_card');
        """
    )


def downgrade() -> None:
    pass
