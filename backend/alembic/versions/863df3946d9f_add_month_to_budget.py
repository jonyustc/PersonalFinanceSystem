"""add month to budget

Revision ID: 863df3946d9f
Revises: a81b0dfa9ec7
Create Date: 2026-05-05 01:14:21.227126
"""
from alembic import op
import sqlalchemy as sa


revision = '863df3946d9f'
down_revision = 'a81b0dfa9ec7'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("budgets", sa.Column(
        "month", sa.String(length=7), nullable=True))

    # Optional: backfill existing rows
    op.execute("UPDATE budgets SET month = '2026-05'")

    op.alter_column("budgets", "month", nullable=False)

    op.create_unique_constraint(
        "uq_budget_user_category_month",
        "budgets",
        ["user_id", "category_id", "month"]
    )

    # op.drop_constraint("uq_budget_period_category", "budgets", type_="unique")


def downgrade() -> None:
    pass
