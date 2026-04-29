from datetime import datetime
from decimal import Decimal
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import extract, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account
from app.models.transaction import Transaction, TransactionType
from app.repositories.account import AccountRepository
from app.repositories.category import CategoryRepository
from app.repositories.transaction import TransactionRepository
from app.schemas.transaction import MonthlySummary, TransactionCreate, TransactionListResponse, TransactionUpdate


class TransactionService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.transactions = TransactionRepository(db)
        self.accounts = AccountRepository(db)
        self.categories = CategoryRepository(db)

    async def _account(self, user_id: UUID, account_id: UUID) -> Account:
        account = await self.accounts.get_user_owned(user_id, account_id)
        if not account:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
        return account

    async def _validate_category(self, user_id: UUID, category_id: UUID | None) -> None:
        if category_id and not await self.categories.get_user_owned(user_id, category_id):
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")

    def _apply_balance(self, account: Account, txn_type: TransactionType, amount: Decimal, reverse: bool = False) -> None:
        multiplier = Decimal("-1") if reverse else Decimal("1")
        if txn_type == TransactionType.EXPENSE:
            account.current_balance -= amount * multiplier
        elif txn_type == TransactionType.INCOME:
            account.current_balance += amount * multiplier

    def _apply_transfer(self, source: Account, destination: Account, amount: Decimal, reverse: bool = False) -> None:
        if reverse:
            source.current_balance += amount
            destination.current_balance -= amount
        else:
            source.current_balance -= amount
            destination.current_balance += amount

    async def create(self, user_id: UUID, payload: TransactionCreate) -> Transaction:
        account = await self._account(user_id, payload.account_id)
        await self._validate_category(user_id, payload.category_id)
        data = payload.model_dump()
        data["user_id"] = user_id
        if payload.txn_type == TransactionType.TRANSFER:
            destination = await self._account(user_id, payload.transfer_account_id)
            self._apply_transfer(account, destination, payload.amount)
        else:
            self._apply_balance(account, payload.txn_type, payload.amount)
        transaction = await self.transactions.create(data)
        await self.db.commit()
        return transaction

    async def list(
        self,
        user_id: UUID,
        start_date: datetime | None,
        end_date: datetime | None,
        account_id: UUID | None,
        category_id: UUID | None,
        limit: int,
        offset: int,
    ) -> TransactionListResponse:
        stmt = self.transactions.filtered_query(user_id, start_date, end_date, account_id, category_id)
        total = await self.transactions.count(stmt)
        items = await self.transactions.list_filtered(stmt, limit, offset)
        return TransactionListResponse(total=total, limit=limit, offset=offset, items=items)

    async def get(self, user_id: UUID, transaction_id: UUID) -> Transaction:
        transaction = await self.transactions.get_user_owned(user_id, transaction_id)
        if not transaction:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Transaction not found")
        return transaction

    async def update(self, user_id: UUID, transaction_id: UUID, payload: TransactionUpdate) -> Transaction:
        old = await self.get(user_id, transaction_id)
        source = await self._account(user_id, old.account_id)
        if old.txn_type == TransactionType.TRANSFER:
            destination = await self._account(user_id, old.transfer_account_id)
            self._apply_transfer(source, destination, old.amount, reverse=True)
        else:
            self._apply_balance(source, old.txn_type, old.amount, reverse=True)

        data = {**old.__dict__, **payload.model_dump(exclude_unset=True)}
        new_payload = TransactionCreate(**{k: data[k] for k in TransactionCreate.model_fields})
        await self._validate_category(user_id, new_payload.category_id)
        new_source = await self._account(user_id, new_payload.account_id)
        if new_payload.txn_type == TransactionType.TRANSFER:
            new_destination = await self._account(user_id, new_payload.transfer_account_id)
            self._apply_transfer(new_source, new_destination, new_payload.amount)
        else:
            self._apply_balance(new_source, new_payload.txn_type, new_payload.amount)
        for field, value in new_payload.model_dump().items():
            setattr(old, field, value)
        await self.db.commit()
        await self.db.refresh(old)
        return old

    async def delete(self, user_id: UUID, transaction_id: UUID) -> None:
        transaction = await self.get(user_id, transaction_id)
        account = await self._account(user_id, transaction.account_id)
        if transaction.txn_type == TransactionType.TRANSFER:
            destination = await self._account(user_id, transaction.transfer_account_id)
            self._apply_transfer(account, destination, transaction.amount, reverse=True)
        else:
            self._apply_balance(account, transaction.txn_type, transaction.amount, reverse=True)
        await self.transactions.delete(transaction)
        await self.db.commit()

    async def monthly_summary(self, user_id: UUID, month: int, year: int) -> MonthlySummary:
        result = await self.db.execute(
            select(Transaction.txn_type, func.coalesce(func.sum(Transaction.amount), 0))
            .where(Transaction.user_id == user_id, extract("month", Transaction.txn_date) == month, extract("year", Transaction.txn_date) == year)
            .group_by(Transaction.txn_type)
        )
        totals = {row[0]: row[1] for row in result.all()}
        income = totals.get(TransactionType.INCOME, Decimal("0"))
        expense = totals.get(TransactionType.EXPENSE, Decimal("0"))
        return MonthlySummary(month=month, year=year, total_income=income, total_expense=expense, savings=income - expense)
