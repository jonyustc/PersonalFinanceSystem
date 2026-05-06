"""add updated_at to categories

Revision ID: e13eae621ebf
Revises: 32a6001a153f
Create Date: 2026-05-03 14:55:55.012380
"""
from alembic import op
import sqlalchemy as sa


revision = 'e13eae621ebf'
down_revision = '32a6001a153f'
branch_labels = None
depends_on = None


def upgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    columns = [col["name"] for col in inspector.get_columns("categories")]

    # ✅ SAFE CHECK
    if "updated_at" not in columns:
        op.add_column(
            "categories",
            sa.Column("updated_at", sa.DateTime(timezone=True), nullable=True),
        )


def downgrade():
    bind = op.get_bind()
    inspector = sa.inspect(bind)

    columns = [col["name"] for col in inspector.get_columns("categories")]

    if "updated_at" in columns:
        op.drop_column("categories", "updated_at")
