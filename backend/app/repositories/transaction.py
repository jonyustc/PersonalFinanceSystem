from datetime import datetime
from uuid import UUID

from sqlalchemy import Select, String, func, or_, select
from sqlalchemy.orm import selectinload

from app.models.category import Category
from app.models.transaction import Transaction
from app.repositories.base import BaseRepository


class TransactionRepository(BaseRepository[Transaction]):
    model = Transaction

    def filtered_query(
        self,
        user_id: UUID,
        start_date: datetime | None = None,
        end_date: datetime | None = None,
        account_id: UUID | None = None,
        category_id: UUID | None = None,
        search: str | None = None,
        txn_type: str | None = None,
        merchant: str | None = None,
        tags: list[str] | None = None,
        recurring_only: bool = False,
        transfer_only: bool = False,
        min_amount=None,
        max_amount=None,
    ) -> Select:
        stmt = select(Transaction).options(
            selectinload(Transaction.account),
            selectinload(Transaction.category),
        ).where(Transaction.user_id == user_id)
        if start_date:
            stmt = stmt.where(Transaction.txn_date >= start_date)
        if end_date:
            stmt = stmt.where(Transaction.txn_date <= end_date)
        if account_id:
            stmt = stmt.where(Transaction.account_id == account_id)
        if category_id:
            stmt = stmt.where(Transaction.category_id == category_id)
        if txn_type:
            stmt = stmt.where(Transaction.type == txn_type)
        if merchant:
            stmt = stmt.where(Transaction.merchant_name.ilike(f"%{merchant}%"))
        if min_amount is not None:
            stmt = stmt.where(Transaction.amount >= min_amount)
        if max_amount is not None:
            stmt = stmt.where(Transaction.amount <= max_amount)
        if recurring_only:
            stmt = stmt.where(Transaction.is_recurring.is_(True))
        if transfer_only:
            stmt = stmt.where(Transaction.type == "transfer")
        if tags:
            stmt = stmt.where(Transaction.tags.overlap(tags))
        if search:
            like = f"%{search}%"
            stmt = stmt.outerjoin(Category, Category.id == Transaction.category_id).where(
                or_(
                    Transaction.description.ilike(like),
                    Transaction.merchant_name.ilike(like),
                    Transaction.reference_number.ilike(like),
                    Category.name.ilike(like),
                    func.array_to_string(Transaction.tags, " ").ilike(like),
                    func.cast(Transaction.amount, String).ilike(like),
                )
            )
        return stmt

    async def list_filtered(self, stmt: Select, limit: int, offset: int) -> list[Transaction]:
        result = await self.db.execute(stmt.order_by(Transaction.txn_date.desc(), Transaction.id.desc()).limit(limit).offset(offset))
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, transaction_id: UUID) -> Transaction | None:
        result = await self.db.execute(select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user_id))
        return result.scalar_one_or_none()
