"""unique transaction reference

Revision ID: 20260606_0002
Revises: 20260606_0001
Create Date: 2026-06-06 22:20:00
"""
from alembic import op


revision = "20260606_0002"
down_revision = "20260606_0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.execute(
        """
        CREATE UNIQUE INDEX IF NOT EXISTS uq_transactions_user_reference
            ON transactions(user_id, reference_number)
            WHERE reference_number IS NOT NULL;
        """
    )


def downgrade() -> None:
    op.execute("DROP INDEX IF EXISTS uq_transactions_user_reference;")
