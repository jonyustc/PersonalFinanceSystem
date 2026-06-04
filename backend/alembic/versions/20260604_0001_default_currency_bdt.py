"""default currency bdt

Revision ID: 20260604_0001
Revises: 20260603_0001
Create Date: 2026-06-04 23:00:00.000000
"""
from alembic import op


revision = "20260604_0001"
down_revision = "20260603_0001"
branch_labels = None
depends_on = None


def upgrade():
    op.execute("ALTER TABLE users ALTER COLUMN currency SET DEFAULT 'BDT'")
    op.execute("ALTER TABLE accounts ALTER COLUMN currency SET DEFAULT 'BDT'")
    op.execute("UPDATE users SET currency = 'BDT' WHERE currency = 'USD'")
    op.execute("UPDATE accounts SET currency = 'BDT' WHERE currency = 'USD'")


def downgrade():
    op.execute("ALTER TABLE users ALTER COLUMN currency SET DEFAULT 'USD'")
    op.execute("ALTER TABLE accounts ALTER COLUMN currency SET DEFAULT 'USD'")
