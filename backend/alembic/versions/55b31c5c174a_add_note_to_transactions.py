"""add note to transactions

Revision ID: 55b31c5c174a
Revises: e13eae621ebf
Create Date: 2026-05-04 12:06:05.693353
"""
from alembic import op
import sqlalchemy as sa


revision = '55b31c5c174a'
down_revision = 'e13eae621ebf'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "transactions",
        sa.Column("note", sa.String(), nullable=True),
    )


def downgrade():
    op.drop_column("transactions", "note")
