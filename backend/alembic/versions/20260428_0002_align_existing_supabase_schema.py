"""align existing Supabase schema

Revision ID: 20260428_0002
Revises: 20260428_0001
Create Date: 2026-04-28 00:10:00
"""
from alembic import op

revision = "20260428_0002"
down_revision = "20260428_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='password_hash'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='hashed_password'
            ) THEN
                ALTER TABLE users RENAME COLUMN password_hash TO hashed_password;
            END IF;

            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='currency'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='default_currency'
            ) THEN
                ALTER TABLE users RENAME COLUMN currency TO default_currency;
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='is_active'
            ) THEN
                ALTER TABLE users ADD COLUMN is_active boolean NOT NULL DEFAULT true;
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='users' AND column_name='updated_at'
            ) THEN
                ALTER TABLE users ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM pg_indexes WHERE schemaname='public' AND tablename='users' AND indexname='ix_users_email'
            ) THEN
                CREATE UNIQUE INDEX ix_users_email ON users (email);
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='accounts' AND column_name='updated_at'
            ) THEN
                ALTER TABLE accounts ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='categories' AND column_name='created_at'
            ) THEN
                ALTER TABLE categories ADD COLUMN created_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='categories' AND column_name='updated_at'
            ) THEN
                ALTER TABLE categories ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='transactions' AND column_name='updated_at'
            ) THEN
                ALTER TABLE transactions ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='transactions' AND column_name='transfer_account_id'
            ) THEN
                ALTER TABLE transactions ADD COLUMN transfer_account_id uuid NULL;
            END IF;
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='transactions' AND column_name='tags' AND data_type <> 'ARRAY'
            ) THEN
                ALTER TABLE transactions ALTER COLUMN tags TYPE varchar[] USING
                    CASE
                        WHEN tags IS NULL OR tags = '' THEN ARRAY[]::varchar[]
                        ELSE ARRAY[tags]::varchar[]
                    END;
            END IF;
            ALTER TABLE transactions ALTER COLUMN tags SET DEFAULT ARRAY[]::varchar[];

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='budgets' AND column_name='updated_at'
            ) THEN
                ALTER TABLE budgets ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='company_name'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='name'
            ) THEN
                ALTER TABLE stocks RENAME COLUMN company_name TO name;
            END IF;
            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='market'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='exchange'
            ) THEN
                ALTER TABLE stocks RENAME COLUMN market TO exchange;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='currency'
            ) THEN
                ALTER TABLE stocks ADD COLUMN currency varchar(3) NOT NULL DEFAULT 'USD';
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='last_price'
            ) THEN
                ALTER TABLE stocks ADD COLUMN last_price numeric(14,4) NOT NULL DEFAULT 0;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='stocks' AND column_name='updated_at'
            ) THEN
                ALTER TABLE stocks ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='portfolio_transactions' AND column_name='broker_fee'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='portfolio_transactions' AND column_name='fees'
            ) THEN
                ALTER TABLE portfolio_transactions RENAME COLUMN broker_fee TO fees;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='portfolio_transactions' AND column_name='created_at'
            ) THEN
                ALTER TABLE portfolio_transactions ADD COLUMN created_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='portfolio_transactions' AND column_name='updated_at'
            ) THEN
                ALTER TABLE portfolio_transactions ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='holdings' AND column_name='total_quantity'
            ) AND NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='holdings' AND column_name='quantity'
            ) THEN
                ALTER TABLE holdings RENAME COLUMN total_quantity TO quantity;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='holdings' AND column_name='realized_profit_loss'
            ) THEN
                ALTER TABLE holdings ADD COLUMN realized_profit_loss numeric(14,2) NOT NULL DEFAULT 0;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='holdings' AND column_name='created_at'
            ) THEN
                ALTER TABLE holdings ADD COLUMN created_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='dividends' AND column_name='notes'
            ) THEN
                ALTER TABLE dividends ADD COLUMN notes varchar(255) NULL;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='dividends' AND column_name='created_at'
            ) THEN
                ALTER TABLE dividends ADD COLUMN created_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='dividends' AND column_name='updated_at'
            ) THEN
                ALTER TABLE dividends ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;

            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='notifications' AND column_name='scheduled_at'
            ) THEN
                ALTER TABLE notifications ADD COLUMN scheduled_at timestamp with time zone NULL;
            END IF;
            IF NOT EXISTS (
                SELECT 1 FROM information_schema.columns
                WHERE table_schema='public' AND table_name='notifications' AND column_name='updated_at'
            ) THEN
                ALTER TABLE notifications ADD COLUMN updated_at timestamp with time zone NOT NULL DEFAULT now();
            END IF;
        END $$;
        """
    )


def downgrade() -> None:
    pass
