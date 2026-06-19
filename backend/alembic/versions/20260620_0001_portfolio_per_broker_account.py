"""portfolios bound to broker accounts

Treats each broker account as a portfolio. Provisions one portfolio per broker
account that has trades, and remaps existing transactions onto it. Trades with no
broker account stay on the per-user default ("My Portfolio").

Revision ID: 20260620_0001
Revises: 20260619_0001
Create Date: 2026-06-20 10:00:00
"""
from alembic import op


revision = "20260620_0001"
down_revision = "20260619_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        ALTER TABLE portfolios
            ADD COLUMN IF NOT EXISTS broker_account_id uuid REFERENCES accounts(id) ON DELETE SET NULL;
        CREATE UNIQUE INDEX IF NOT EXISTS uq_portfolio_broker_account
            ON portfolios(user_id, broker_account_id) WHERE broker_account_id IS NOT NULL;

        -- One portfolio per broker account that has trades. Kind inferred from the
        -- account name so SIP vs Trading is sensible out of the box (editable later).
        INSERT INTO portfolios (id, user_id, name, kind, is_default, broker_account_id, created_at, updated_at)
        SELECT
            gen_random_uuid(),
            a.user_id,
            a.name,
            CASE
                WHEN a.name ILIKE '%trade%' THEN 'mid_term_trading'
                WHEN a.name ILIKE '%invest%' OR a.name ILIKE '%sip%' THEN 'long_term_sip'
                ELSE 'general'
            END,
            false,
            a.id,
            now(),
            now()
        FROM accounts a
        WHERE EXISTS (
            SELECT 1 FROM portfolio_transactions t
            WHERE t.broker_account_id = a.id AND t.user_id = a.user_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM portfolios p
            WHERE p.user_id = a.user_id AND p.broker_account_id = a.id
        );

        -- Point each trade at its broker account's portfolio.
        UPDATE portfolio_transactions t
        SET portfolio_id = p.id
        FROM portfolios p
        WHERE p.broker_account_id = t.broker_account_id
          AND p.user_id = t.user_id
          AND t.broker_account_id IS NOT NULL;

        -- Mirror onto derived dividends (holdings/dividends are also rebuilt on next read).
        UPDATE dividends d
        SET portfolio_id = p.id
        FROM portfolios p, portfolio_transactions t
        WHERE t.id = (
            SELECT t2.id FROM portfolio_transactions t2
            WHERE t2.user_id = d.user_id AND t2.stock_id = d.stock_id AND t2.txn_type = 'income'
            ORDER BY t2.txn_date DESC LIMIT 1
        )
        AND p.id = t.portfolio_id
        AND t.broker_account_id IS NOT NULL;
        """
    )


def downgrade() -> None:
    op.execute(
        """
        DROP INDEX IF EXISTS uq_portfolio_broker_account;
        DELETE FROM portfolios WHERE broker_account_id IS NOT NULL;
        ALTER TABLE portfolios DROP COLUMN IF EXISTS broker_account_id;
        """
    )
