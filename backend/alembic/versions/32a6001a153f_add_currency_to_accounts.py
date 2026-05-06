"""add currency to accounts (safe)

Revision ID: 32a6001a153f
Revises: adf820b8b33f
Create Date: 2026-05-03
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy import inspect


# revision identifiers
revision = "32a6001a153f"
down_revision = "adf820b8b33f"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    columns = [col["name"] for col in inspector.get_columns("accounts")]

    # ✅ ADD ONLY IF NOT EXISTS

    if "currency" not in columns:
        op.add_column(
            "accounts",
            sa.Column("currency", sa.String(length=3),
                      nullable=False, server_default="USD"),
        )

    if "notes" not in columns:
        op.add_column(
            "accounts",
            sa.Column("notes", sa.String(), nullable=True),
        )

    if "is_active" not in columns:
        op.add_column(
            "accounts",
            sa.Column("is_active", sa.Boolean(),
                      nullable=False, server_default="true"),
        )

    if "updated_at" not in columns:
        op.add_column(
            "accounts",
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        )


def downgrade() -> None:
    bind = op.get_bind()
    inspector = inspect(bind)

    columns = [col["name"] for col in inspector.get_columns("accounts")]

    # ✅ DROP ONLY IF EXISTS

    if "updated_at" in columns:
        op.drop_column("accounts", "updated_at")

    if "is_active" in columns:
        op.drop_column("accounts", "is_active")

    if "notes" in columns:
        op.drop_column("accounts", "notes")

    if "currency" in columns:
        op.drop_column("accounts", "currency")
