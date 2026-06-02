"""add opening balance to monthly income

Revision ID: 20260602_0004
Revises: 20260602_0003
Create Date: 2026-06-02 19:10:00
"""
from alembic import op
import sqlalchemy as sa


revision = "20260602_0004"
down_revision = "20260602_0003"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "monthly_income",
        sa.Column(
            "opening_balance",
            sa.Numeric(14, 2),
            nullable=False,
            server_default="0",
        ),
    )
    op.alter_column("monthly_income", "opening_balance", server_default=None)


def downgrade() -> None:
    op.drop_column("monthly_income", "opening_balance")
