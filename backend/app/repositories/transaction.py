from datetime import datetime
from uuid import UUID

from sqlalchemy import Select, select

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
    ) -> Select:
        stmt = select(Transaction).where(Transaction.user_id == user_id)
        if start_date:
            stmt = stmt.where(Transaction.txn_date >= start_date)
        if end_date:
            stmt = stmt.where(Transaction.txn_date <= end_date)
        if account_id:
            stmt = stmt.where(Transaction.account_id == account_id)
        if category_id:
            stmt = stmt.where(Transaction.category_id == category_id)
        return stmt

    async def list_filtered(self, stmt: Select, limit: int, offset: int) -> list[Transaction]:
        result = await self.db.execute(stmt.order_by(Transaction.txn_date.desc()).limit(limit).offset(offset))
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, transaction_id: UUID) -> Transaction | None:
        result = await self.db.execute(select(Transaction).where(Transaction.id == transaction_id, Transaction.user_id == user_id))
        return result.scalar_one_or_none()
