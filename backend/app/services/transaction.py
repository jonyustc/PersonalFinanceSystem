from uuid import UUID
from typing import Optional
from datetime import date, timedelta

from fastapi import HTTPException
from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction
from app.models.account import Account
from app.schemas.transaction import TransactionCreate, TransactionUpdate


class TransactionService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # ================= CREATE =================

    async def create(self, user_id: UUID, payload: TransactionCreate):
        from_acc = await self._get_account(user_id, payload.account_id)
        to_acc = None

        if payload.type == "transfer":
            to_acc = await self._get_account(user_id, payload.transfer_account_id)

        await self._apply_balance(from_acc, to_acc, payload)

        trx = Transaction(
            user_id=user_id,
            account_id=payload.account_id,
            transfer_account_id=payload.transfer_account_id,
            category_id=payload.category_id,
            type=payload.type,
            payment_method=payload.payment_method,
            amount=payload.amount,
            txn_date=payload.txn_date,
            is_emergency=payload.is_emergency,
            description=payload.description,
        )

        self.db.add(trx)
        await self.db.commit()
        await self.db.refresh(trx)

        return trx

    # ================= LIST =================

    async def list(
        self,
        user_id: UUID,
        limit: int = 50,
        offset: int = 0,
        search: Optional[str] = None,
        type: Optional[str] = None,
        category_id: Optional[UUID] = None,
        account_id: Optional[UUID] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
    ):
        filters = [Transaction.user_id == user_id]

        if search:
            filters.append(Transaction.description.ilike(f"%{search}%"))

        if type:
            filters.append(Transaction.type == type)

        if category_id:
            filters.append(Transaction.category_id == category_id)

        if account_id:
            filters.append(Transaction.account_id == account_id)

        if from_date:
            filters.append(Transaction.txn_date >= from_date)

        if to_date:
            filters.append(Transaction.txn_date < to_date + timedelta(days=1))

        stmt = (
            select(Transaction)
            .where(and_(*filters))
            .order_by(Transaction.txn_date.desc())
            .limit(limit)
            .offset(offset)
        )

        result = await self.db.execute(stmt)
        items = result.scalars().all()

        count_stmt = select(func.count()).select_from(
            Transaction).where(and_(*filters))
        total = await self.db.scalar(count_stmt)

        return items, total

    # ================= UPDATE =================

    async def update(self, user_id: UUID, transaction_id: UUID, payload: TransactionUpdate):
        trx = await self.db.get(Transaction, transaction_id)

        if not trx or trx.user_id != user_id:
            return None

        # 🔄 reverse old
        old_from = await self._get_account(user_id, trx.account_id)
        old_to = None

        if trx.type == "transfer":
            old_to = await self._get_account(user_id, trx.transfer_account_id)

        await self._reverse_balance(old_from, old_to, trx)

        # apply new values
        update_data = payload.dict(exclude_unset=True)

        for field, value in update_data.items():
            setattr(trx, field, value)

        new_from = await self._get_account(user_id, trx.account_id)
        new_to = None

        if trx.type == "transfer":
            new_to = await self._get_account(user_id, trx.transfer_account_id)

        await self._apply_balance(new_from, new_to, trx)

        await self.db.commit()
        await self.db.refresh(trx)

        return trx

    # ================= DELETE =================

    async def delete(self, user_id: UUID, transaction_id: UUID):
        trx = await self.db.get(Transaction, transaction_id)

        if not trx or trx.user_id != user_id:
            return False

        from_acc = await self._get_account(user_id, trx.account_id)
        to_acc = None

        if trx.type == "transfer":
            to_acc = await self._get_account(user_id, trx.transfer_account_id)

        await self._reverse_balance(from_acc, to_acc, trx)

        await self.db.delete(trx)
        await self.db.commit()

        return True

    # ================= BALANCE ENGINE =================

    async def _apply_balance(self, from_acc: Account, to_acc: Optional[Account], trx):
        is_card_from = from_acc.type == "card"
        is_card_to = to_acc.type == "card" if to_acc else False

        # EXPENSE
        if trx.type == "expense":
            if is_card_from:
                from_acc.balance -= trx.amount
            else:
                if from_acc.balance < trx.amount:
                    raise HTTPException(400, "Insufficient balance")
                from_acc.balance -= trx.amount

        # INCOME
        elif trx.type == "income":
            from_acc.balance += trx.amount

        # TRANSFER
        elif trx.type == "transfer":
            if not to_acc:
                raise HTTPException(400, "Transfer account required")

            # BANK → CARD (payment)
            if not is_card_from and is_card_to:
                if from_acc.balance < trx.amount:
                    raise HTTPException(400, "Insufficient balance")

                from_acc.balance -= trx.amount
                to_acc.balance += trx.amount

            # CARD → BANK
            elif is_card_from and not is_card_to:
                from_acc.balance -= trx.amount
                to_acc.balance += trx.amount

            # NORMAL
            else:
                if from_acc.balance < trx.amount:
                    raise HTTPException(400, "Insufficient balance")

                from_acc.balance -= trx.amount
                to_acc.balance += trx.amount

    async def _reverse_balance(self, from_acc: Account, to_acc: Optional[Account], trx):
        is_card_from = from_acc.type == "card"
        is_card_to = to_acc.type == "card" if to_acc else False

        if trx.type == "expense":
            from_acc.balance += trx.amount

        elif trx.type == "income":
            from_acc.balance -= trx.amount

        elif trx.type == "transfer":
            if not to_acc:
                return

            # BANK → CARD
            if not is_card_from and is_card_to:
                from_acc.balance += trx.amount
                to_acc.balance -= trx.amount

            # CARD → BANK
            elif is_card_from and not is_card_to:
                from_acc.balance += trx.amount
                to_acc.balance -= trx.amount

            # NORMAL
            else:
                from_acc.balance += trx.amount
                to_acc.balance -= trx.amount

    # ================= HELPERS =================

    async def _get_account(self, user_id: UUID, account_id: UUID) -> Account:
        acc = await self.db.get(Account, account_id)

        if not acc or acc.user_id != user_id:
            raise HTTPException(404, "Account not found")

        return acc
