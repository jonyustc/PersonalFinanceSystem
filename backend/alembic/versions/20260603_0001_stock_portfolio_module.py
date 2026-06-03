"""stock portfolio module

Revision ID: 20260603_0001
Revises: 20260602_0004
Create Date: 2026-06-03 10:00:00
"""
from alembic import op


revision = "20260603_0001"
down_revision = "20260602_0004"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE TABLE IF NOT EXISTS stocks (
            id uuid PRIMARY KEY,
            symbol varchar(20) NOT NULL,
            name varchar(255) NOT NULL,
            exchange varchar(80),
            currency varchar(3) NOT NULL DEFAULT 'BDT',
            last_price numeric(14,4) NOT NULL DEFAULT 0,
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now()
        );
        CREATE UNIQUE INDEX IF NOT EXISTS ix_stocks_symbol ON stocks(symbol);

        CREATE TABLE IF NOT EXISTS portfolio_transactions (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            stock_id uuid REFERENCES stocks(id) ON DELETE RESTRICT,
            broker_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL,
            txn_type varchar(20) NOT NULL,
            quantity numeric(18,6) NOT NULL DEFAULT 0,
            price numeric(14,4) NOT NULL DEFAULT 0,
            fees numeric(14,2) NOT NULL DEFAULT 0,
            txn_date date NOT NULL,
            notes varchar(255),
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now()
        );
        ALTER TABLE portfolio_transactions ALTER COLUMN stock_id DROP NOT NULL;
        ALTER TABLE portfolio_transactions ADD COLUMN IF NOT EXISTS broker_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL;
        ALTER TABLE portfolio_transactions ADD COLUMN IF NOT EXISTS notes varchar(255);
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_user_id ON portfolio_transactions(user_id);
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_stock_id ON portfolio_transactions(stock_id);
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_broker_account_id ON portfolio_transactions(broker_account_id);
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_txn_date ON portfolio_transactions(txn_date);
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_txn_type ON portfolio_transactions(txn_type);

        CREATE TABLE IF NOT EXISTS holdings (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            stock_id uuid NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
            quantity numeric(18,6) NOT NULL DEFAULT 0,
            avg_buy_price numeric(14,4) NOT NULL DEFAULT 0,
            realized_profit_loss numeric(14,2) NOT NULL DEFAULT 0,
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now(),
            CONSTRAINT uq_user_stock_holding UNIQUE(user_id, stock_id)
        );
        CREATE INDEX IF NOT EXISTS ix_holdings_user_id ON holdings(user_id);
        CREATE INDEX IF NOT EXISTS ix_holdings_stock_id ON holdings(stock_id);

        CREATE TABLE IF NOT EXISTS dividends (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            stock_id uuid NOT NULL REFERENCES stocks(id) ON DELETE CASCADE,
            amount numeric(14,2) NOT NULL,
            payment_date date NOT NULL,
            notes varchar(255),
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_dividends_user_id ON dividends(user_id);
        CREATE INDEX IF NOT EXISTS ix_dividends_stock_id ON dividends(stock_id);
        CREATE INDEX IF NOT EXISTS ix_dividends_payment_date ON dividends(payment_date);
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS ix_portfolio_transactions_broker_account_id;")
    op.execute("ALTER TABLE portfolio_transactions DROP COLUMN IF EXISTS broker_account_id;")
    op.execute("ALTER TABLE portfolio_transactions DROP COLUMN IF EXISTS notes;")
