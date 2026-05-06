"""fix transactions columns

Revision ID: a81b0dfa9ec7
Revises: 55b31c5c174a
Create Date: 2026-05-04 12:09:28.933518
"""
from alembic import op
import sqlalchemy as sa


revision = 'a81b0dfa9ec7'
down_revision = '55b31c5c174a'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "transactions",
        sa.Column("transaction_date", sa.DateTime(
            timezone=True), nullable=True),
    )

    op.add_column(
        "transactions",
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade():
    op.drop_column("transactions", "transaction_date")
    op.drop_column("transactions", "updated_at")
