"""simple dashboard card account fields

Revision ID: 20260601_0001
Revises: 20260507_0001
Create Date: 2026-06-01 00:00:00
"""
from alembic import op


revision = "20260601_0001"
down_revision = "20260507_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE accounts
            ADD COLUMN IF NOT EXISTS credit_limit NUMERIC(14,2),
            ADD COLUMN IF NOT EXISTS current_outstanding NUMERIC(14,2) NOT NULL DEFAULT 0,
            ADD COLUMN IF NOT EXISTS billing_cycle_day INTEGER,
            ADD COLUMN IF NOT EXISTS payment_due_day INTEGER;

        UPDATE accounts a
        SET
            credit_limit = COALESCE(a.credit_limit, c.credit_limit),
            billing_cycle_day = COALESCE(a.billing_cycle_day, c.statement_day),
            payment_due_day = COALESCE(a.payment_due_day, c.due_day)
        FROM credit_card_details c
        WHERE c.account_id = a.id;

        UPDATE accounts
        SET current_outstanding = GREATEST(ABS(balance), 0)
        WHERE current_outstanding = 0
          AND lower(type) IN ('card', 'credit_card')
          AND balance < 0;

        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_schema='public'
                  AND table_name='accounts'
                  AND constraint_name='ck_accounts_credit_limit_nonnegative'
            ) THEN
                ALTER TABLE accounts
                    ADD CONSTRAINT ck_accounts_credit_limit_nonnegative
                    CHECK (credit_limit IS NULL OR credit_limit >= 0);
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_schema='public'
                  AND table_name='accounts'
                  AND constraint_name='ck_accounts_current_outstanding_nonnegative'
            ) THEN
                ALTER TABLE accounts
                    ADD CONSTRAINT ck_accounts_current_outstanding_nonnegative
                    CHECK (current_outstanding >= 0);
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_schema='public'
                  AND table_name='accounts'
                  AND constraint_name='ck_accounts_billing_cycle_day'
            ) THEN
                ALTER TABLE accounts
                    ADD CONSTRAINT ck_accounts_billing_cycle_day
                    CHECK (billing_cycle_day IS NULL OR billing_cycle_day BETWEEN 1 AND 31);
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_schema='public'
                  AND table_name='accounts'
                  AND constraint_name='ck_accounts_payment_due_day'
            ) THEN
                ALTER TABLE accounts
                    ADD CONSTRAINT ck_accounts_payment_due_day
                    CHECK (payment_due_day IS NULL OR payment_due_day BETWEEN 1 AND 31);
            END IF;
        END $$;

        CREATE INDEX IF NOT EXISTS ix_transactions_transaction_date ON transactions(transaction_date);
        CREATE INDEX IF NOT EXISTS ix_transactions_transaction_type ON transactions(transaction_type);
        CREATE INDEX IF NOT EXISTS ix_accounts_user_active_type ON accounts(user_id, is_active, type);
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS ix_accounts_user_active_type;
        DROP INDEX IF EXISTS ix_transactions_transaction_type;
        DROP INDEX IF EXISTS ix_transactions_transaction_date;

        ALTER TABLE accounts DROP CONSTRAINT IF EXISTS ck_accounts_payment_due_day;
        ALTER TABLE accounts DROP CONSTRAINT IF EXISTS ck_accounts_billing_cycle_day;
        ALTER TABLE accounts DROP CONSTRAINT IF EXISTS ck_accounts_current_outstanding_nonnegative;
        ALTER TABLE accounts DROP CONSTRAINT IF EXISTS ck_accounts_credit_limit_nonnegative;

        ALTER TABLE accounts
            DROP COLUMN IF EXISTS payment_due_day,
            DROP COLUMN IF EXISTS billing_cycle_day,
            DROP COLUMN IF EXISTS current_outstanding,
            DROP COLUMN IF EXISTS credit_limit;
        """
    )
