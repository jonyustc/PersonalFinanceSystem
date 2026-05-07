"""transactions fintech phase 1

Revision ID: 20260507_0001
Revises: 20260506_0001
Create Date: 2026-05-07 00:00:00
"""
from alembic import op


revision = "20260507_0001"
down_revision = "20260506_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE transactions
            ADD COLUMN IF NOT EXISTS merchant_name varchar(160),
            ADD COLUMN IF NOT EXISTS transaction_type varchar(20),
            ADD COLUMN IF NOT EXISTS transfer_id uuid,
            ADD COLUMN IF NOT EXISTS tags varchar[] NOT NULL DEFAULT ARRAY[]::varchar[],
            ADD COLUMN IF NOT EXISTS location varchar(160),
            ADD COLUMN IF NOT EXISTS attachment_url text,
            ADD COLUMN IF NOT EXISTS recurring_rule varchar(20),
            ADD COLUMN IF NOT EXISTS parent_transaction_id uuid,
            ADD COLUMN IF NOT EXISTS is_split boolean NOT NULL DEFAULT false,
            ADD COLUMN IF NOT EXISTS is_recurring boolean NOT NULL DEFAULT false,
            ADD COLUMN IF NOT EXISTS transaction_status varchar(20) NOT NULL DEFAULT 'posted',
            ADD COLUMN IF NOT EXISTS reference_number varchar(80);

        UPDATE transactions
        SET
            transaction_type = COALESCE(transaction_type, type),
            tags = COALESCE(tags, ARRAY[]::varchar[]),
            is_split = COALESCE(is_split, false),
            is_recurring = COALESCE(is_recurring, false),
            transaction_status = COALESCE(transaction_status, 'posted'),
            transaction_date = COALESCE(transaction_date, txn_date),
            updated_at = COALESCE(updated_at, now()),
            created_at = COALESCE(created_at, now());

        ALTER TABLE transactions
            ALTER COLUMN tags SET NOT NULL,
            ALTER COLUMN is_split SET NOT NULL,
            ALTER COLUMN is_recurring SET NOT NULL,
            ALTER COLUMN transaction_status SET NOT NULL,
            ALTER COLUMN created_at SET DEFAULT now(),
            ALTER COLUMN updated_at SET DEFAULT now();

        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.table_constraints
                WHERE table_schema='public'
                  AND table_name='transactions'
                  AND constraint_name='fk_transactions_parent'
            ) THEN
                ALTER TABLE transactions
                    ADD CONSTRAINT fk_transactions_parent
                    FOREIGN KEY (parent_transaction_id) REFERENCES transactions(id) ON DELETE SET NULL;
            END IF;
        END $$;

        CREATE INDEX IF NOT EXISTS ix_transactions_user_id ON transactions(user_id);
        CREATE INDEX IF NOT EXISTS ix_transactions_category_id ON transactions(category_id);
        CREATE INDEX IF NOT EXISTS ix_transactions_account_id ON transactions(account_id);
        CREATE INDEX IF NOT EXISTS ix_transactions_txn_date ON transactions(txn_date DESC);
        CREATE INDEX IF NOT EXISTS ix_transactions_merchant_name ON transactions(lower(merchant_name));
        CREATE INDEX IF NOT EXISTS ix_transactions_tags ON transactions USING gin(tags);
        """
    )


def downgrade() -> None:
    pass
