"""fintech accounts phase 1

Revision ID: 20260506_0001
Revises: d07dfdeea75e
Create Date: 2026-05-06 00:00:00
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql


revision = "20260506_0001"
down_revision = "d07dfdeea75e"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    op.execute(
        """
        ALTER TABLE accounts
            ADD COLUMN IF NOT EXISTS opening_balance NUMERIC(14,2),
            ADD COLUMN IF NOT EXISTS account_subtype VARCHAR(30),
            ADD COLUMN IF NOT EXISTS institution_name VARCHAR(120),
            ADD COLUMN IF NOT EXISTS color VARCHAR(20),
            ADD COLUMN IF NOT EXISTS icon VARCHAR(50),
            ADD COLUMN IF NOT EXISTS archived BOOLEAN NOT NULL DEFAULT false;

        UPDATE accounts
        SET
            balance = COALESCE(balance, 0),
            currency = upper(COALESCE(currency, 'USD')),
            created_at = COALESCE(created_at, now()),
            updated_at = COALESCE(updated_at, now());

        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='accounts' AND column_name='balance'
            ) THEN
                UPDATE accounts
                SET opening_balance = COALESCE(opening_balance, balance, 0)
                WHERE opening_balance IS NULL;
            ELSIF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='accounts' AND column_name='current_balance'
            ) THEN
                UPDATE accounts
                SET opening_balance = COALESCE(opening_balance, current_balance, 0)
                WHERE opening_balance IS NULL;
            ELSE
                UPDATE accounts
                SET opening_balance = COALESCE(opening_balance, 0)
                WHERE opening_balance IS NULL;
            END IF;
        END $$;

        ALTER TABLE accounts
            ALTER COLUMN balance SET DEFAULT 0,
            ALTER COLUMN balance SET NOT NULL,
            ALTER COLUMN currency SET DEFAULT 'USD',
            ALTER COLUMN currency SET NOT NULL,
            ALTER COLUMN created_at SET DEFAULT now(),
            ALTER COLUMN created_at SET NOT NULL,
            ALTER COLUMN updated_at SET DEFAULT now(),
            ALTER COLUMN updated_at SET NOT NULL,
            ALTER COLUMN opening_balance SET DEFAULT 0,
            ALTER COLUMN opening_balance SET NOT NULL;
        """
    )

    op.create_table(
        "credit_card_details",
        sa.Column(
            "account_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("accounts.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("credit_limit", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("available_credit", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("statement_day", sa.Integer(), nullable=True),
        sa.Column("due_day", sa.Integer(), nullable=True),
        sa.Column("minimum_payment_percent", sa.Numeric(5, 2), nullable=False, server_default="0"),
        sa.Column("annual_fee", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("interest_rate", sa.Numeric(6, 3), nullable=False, server_default="0"),
        sa.Column("auto_pay_enabled", sa.Boolean(), nullable=False, server_default="false"),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("credit_limit >= 0", name="ck_credit_card_details_credit_limit_nonnegative"),
        sa.CheckConstraint("statement_day IS NULL OR statement_day BETWEEN 1 AND 31", name="ck_credit_card_details_statement_day"),
        sa.CheckConstraint("due_day IS NULL OR due_day BETWEEN 1 AND 31", name="ck_credit_card_details_due_day"),
    )

    op.create_table(
        "account_transfers",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("from_account_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("to_account_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("accounts.id", ondelete="RESTRICT"), nullable=False),
        sa.Column("amount", sa.Numeric(14, 2), nullable=False),
        sa.Column("fee", sa.Numeric(14, 2), nullable=False, server_default="0"),
        sa.Column("notes", sa.String(), nullable=True),
        sa.Column("transfer_date", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.CheckConstraint("amount > 0", name="ck_account_transfers_amount_positive"),
        sa.CheckConstraint("fee >= 0", name="ck_account_transfers_fee_nonnegative"),
        sa.CheckConstraint("from_account_id <> to_account_id", name="ck_account_transfers_distinct_accounts"),
    )
    op.create_index("ix_account_transfers_user_id", "account_transfers", ["user_id"])
    op.create_index("ix_account_transfers_from_account_id", "account_transfers", ["from_account_id"])
    op.create_index("ix_account_transfers_to_account_id", "account_transfers", ["to_account_id"])

    op.create_table(
        "account_balance_history",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True, server_default=sa.text("gen_random_uuid()")),
        sa.Column("account_id", postgresql.UUID(as_uuid=True), sa.ForeignKey("accounts.id", ondelete="CASCADE"), nullable=False),
        sa.Column("balance_date", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("closing_balance", sa.Numeric(14, 2), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.text("now()")),
    )
    op.create_index("ix_account_balance_history_account_id", "account_balance_history", ["account_id"])
    op.create_index("ix_account_balance_history_balance_date", "account_balance_history", ["balance_date"])

    op.execute(
        """
        INSERT INTO credit_card_details (
            account_id,
            credit_limit,
            available_credit,
            statement_day,
            due_day,
            minimum_payment_percent,
            annual_fee,
            interest_rate,
            auto_pay_enabled
        )
        SELECT
            id,
            0,
            0,
            NULL,
            NULL,
            0,
            0,
            0,
            false
        FROM accounts
        WHERE type = 'card'
        ON CONFLICT (account_id) DO NOTHING;

        INSERT INTO account_balance_history (account_id, balance_date, closing_balance)
        SELECT id, now(), balance
        FROM accounts
        ON CONFLICT DO NOTHING;
        """
    )


def downgrade() -> None:
    op.drop_index("ix_account_balance_history_balance_date", table_name="account_balance_history")
    op.drop_index("ix_account_balance_history_account_id", table_name="account_balance_history")
    op.drop_table("account_balance_history")

    op.drop_index("ix_account_transfers_to_account_id", table_name="account_transfers")
    op.drop_index("ix_account_transfers_from_account_id", table_name="account_transfers")
    op.drop_index("ix_account_transfers_user_id", table_name="account_transfers")
    op.drop_table("account_transfers")

    op.drop_table("credit_card_details")

    for column_name in [
        "archived",
        "icon",
        "color",
        "institution_name",
        "account_subtype",
        "opening_balance",
    ]:
        op.drop_column("accounts", column_name)
