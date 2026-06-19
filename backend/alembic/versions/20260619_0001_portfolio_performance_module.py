"""portfolio performance & analytics module

Adds named portfolios (SIP / Trading / general), a daily value snapshot table,
and links existing portfolio rows to a per-user default portfolio.

Revision ID: 20260619_0001
Revises: 20260606_0002
Create Date: 2026-06-19 10:00:00
"""
from alembic import op


revision = "20260619_0001"
down_revision = "20260606_0002"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        -- Named portfolios (Long-Term SIP / Mid-Term Trading / general)
        CREATE TABLE IF NOT EXISTS portfolios (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            name varchar(120) NOT NULL,
            kind varchar(30) NOT NULL DEFAULT 'general',
            description varchar(255),
            is_default boolean NOT NULL DEFAULT false,
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_portfolios_user_id ON portfolios(user_id);
        CREATE UNIQUE INDEX IF NOT EXISTS uq_portfolio_user_name ON portfolios(user_id, name);

        -- Daily point-in-time valuation snapshots (captured lazily on summary read)
        CREATE TABLE IF NOT EXISTS portfolio_value_snapshots (
            id uuid PRIMARY KEY,
            user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
            portfolio_id uuid NOT NULL REFERENCES portfolios(id) ON DELETE CASCADE,
            snapshot_date date NOT NULL,
            equity_value numeric(18,2) NOT NULL DEFAULT 0,
            cash_balance numeric(18,2) NOT NULL DEFAULT 0,
            total_value numeric(18,2) NOT NULL DEFAULT 0,
            invested_capital numeric(18,2) NOT NULL DEFAULT 0,
            realized_gain numeric(18,2) NOT NULL DEFAULT 0,
            unrealized_gain numeric(18,2) NOT NULL DEFAULT 0,
            dividend_income numeric(18,2) NOT NULL DEFAULT 0,
            total_return numeric(18,2) NOT NULL DEFAULT 0,
            created_at timestamp with time zone NOT NULL DEFAULT now(),
            updated_at timestamp with time zone NOT NULL DEFAULT now()
        );
        CREATE INDEX IF NOT EXISTS ix_portfolio_value_snapshots_user_id ON portfolio_value_snapshots(user_id);
        CREATE INDEX IF NOT EXISTS ix_portfolio_value_snapshots_portfolio_id ON portfolio_value_snapshots(portfolio_id);
        CREATE INDEX IF NOT EXISTS ix_portfolio_value_snapshots_snapshot_date ON portfolio_value_snapshots(snapshot_date);
        CREATE UNIQUE INDEX IF NOT EXISTS uq_portfolio_snapshot_day
            ON portfolio_value_snapshots(user_id, portfolio_id, snapshot_date);

        -- Link existing portfolio rows to a portfolio
        ALTER TABLE portfolio_transactions ADD COLUMN IF NOT EXISTS portfolio_id uuid REFERENCES portfolios(id) ON DELETE CASCADE;
        ALTER TABLE holdings ADD COLUMN IF NOT EXISTS portfolio_id uuid REFERENCES portfolios(id) ON DELETE CASCADE;
        ALTER TABLE dividends ADD COLUMN IF NOT EXISTS portfolio_id uuid REFERENCES portfolios(id) ON DELETE CASCADE;
        CREATE INDEX IF NOT EXISTS ix_portfolio_transactions_portfolio_id ON portfolio_transactions(portfolio_id);
        CREATE INDEX IF NOT EXISTS ix_holdings_portfolio_id ON holdings(portfolio_id);
        CREATE INDEX IF NOT EXISTS ix_dividends_portfolio_id ON dividends(portfolio_id);

        -- Create one default portfolio per user that has any portfolio activity
        INSERT INTO portfolios (id, user_id, name, kind, is_default, created_at, updated_at)
        SELECT gen_random_uuid(), u.user_id, 'My Portfolio', 'general', true, now(), now()
        FROM (
            SELECT user_id FROM portfolio_transactions
            UNION
            SELECT user_id FROM holdings
            UNION
            SELECT user_id FROM dividends
        ) AS u
        WHERE NOT EXISTS (
            SELECT 1 FROM portfolios p WHERE p.user_id = u.user_id
        )
        -- Skip rows belonging to deleted users (historical un-cascaded orphans);
        -- they are never queried since the app always filters by the current user.
        AND EXISTS (
            SELECT 1 FROM users usr WHERE usr.id = u.user_id
        );

        -- Assign orphaned rows to their user's default portfolio
        UPDATE portfolio_transactions t
        SET portfolio_id = p.id
        FROM portfolios p
        WHERE p.user_id = t.user_id AND p.is_default = true AND t.portfolio_id IS NULL;

        UPDATE holdings h
        SET portfolio_id = p.id
        FROM portfolios p
        WHERE p.user_id = h.user_id AND p.is_default = true AND h.portfolio_id IS NULL;

        UPDATE dividends d
        SET portfolio_id = p.id
        FROM portfolios p
        WHERE p.user_id = d.user_id AND p.is_default = true AND d.portfolio_id IS NULL;

        -- Swap the holdings uniqueness to be per-portfolio
        ALTER TABLE holdings DROP CONSTRAINT IF EXISTS uq_user_stock_holding;
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM pg_constraint WHERE conname = 'uq_user_portfolio_stock_holding'
            ) THEN
                ALTER TABLE holdings
                    ADD CONSTRAINT uq_user_portfolio_stock_holding UNIQUE (user_id, portfolio_id, stock_id);
            END IF;
        END$$;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        ALTER TABLE holdings DROP CONSTRAINT IF EXISTS uq_user_portfolio_stock_holding;
        ALTER TABLE portfolio_transactions DROP COLUMN IF EXISTS portfolio_id;
        ALTER TABLE holdings DROP COLUMN IF EXISTS portfolio_id;
        ALTER TABLE dividends DROP COLUMN IF EXISTS portfolio_id;
        DROP TABLE IF EXISTS portfolio_value_snapshots;
        DROP TABLE IF EXISTS portfolios;
        """
    )
