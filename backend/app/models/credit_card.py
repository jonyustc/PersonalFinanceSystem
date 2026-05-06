# models/credit_card.py

from sqlalchemy import ForeignKey, Numeric
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import mapped_column

from app.db.session import Base
from app.models.base import UUIDMixin


class CreditCard(UUIDMixin, Base):
    __tablename__ = "credit_cards"

    account_id = mapped_column(UUID(as_uuid=True), ForeignKey("accounts.id"))
    limit = mapped_column(Numeric(14, 2))
    outstanding = mapped_column(Numeric(14, 2), default=0)
