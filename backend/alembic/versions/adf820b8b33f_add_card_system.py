"""add card system

Revision ID: adf820b8b33f
Revises: 20260428_0002
Create Date: 2026-05-02 15:22:22.846760
"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = 'adf820b8b33f'
down_revision = '20260428_0002'
branch_labels = None
depends_on = None


def upgrade() -> None:

    # ✅ ADD payment_method (safe)
    op.add_column(
        'transactions',
        sa.Column('payment_method', sa.String(length=20),
                  nullable=False, server_default='cash')
    )

    # ✅ ADD is_emergency (FIXED)
    op.add_column(
        'transactions',
        sa.Column('is_emergency', sa.Boolean(),
                  nullable=False, server_default='false')
    )

    # OPTIONAL CLEANUP (remove default after data populated)
    op.alter_column('transactions', 'payment_method', server_default=None)
    op.alter_column('transactions', 'is_emergency', server_default=None)


def downgrade() -> None:
    op.drop_column('transactions', 'is_emergency')
    op.drop_column('transactions', 'payment_method')
    op.drop_table('credit_cards')
