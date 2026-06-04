from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Optional
from uuid import UUID

from fastapi import HTTPException
from sqlalchemy import String, case, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.account import Account, AccountBalanceHistory
from app.models.transaction import Transaction
from app.schemas.transaction import BulkTransactionUpdate, SplitTransactionCreate, TransactionCreate, TransactionUpdate
from app.services.account import is_credit_card


ZERO = Decimal("0")


class TransactionService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create(self, user_id: UUID, payload: TransactionCreate):
        try:
            trx = await self._build_and_apply(user_id, payload)
            await self.db.commit()
            await self.db.refresh(trx)
            return trx
        except Exception:
            await self.db.rollback()
            raise

    async def list(
        self,
        user_id: UUID,
        limit: int = 50,
        offset: int = 0,
        search: Optional[str] = None,
        type: Optional[str] = None,
        account_source: Optional[str] = None,
        category_id: Optional[UUID] = None,
        account_id: Optional[UUID] = None,
        from_date: Optional[date] = None,
        to_date: Optional[date] = None,
        merchant: Optional[str] = None,
        tags: Optional[list[str]] = None,
        recurring_only: bool = False,
        transfer_only: bool = False,
        min_amount: Optional[Decimal] = None,
        max_amount: Optional[Decimal] = None,
    ):
        filters = [Transaction.user_id == user_id]
        if search:
            like = f"%{search}%"
            filters.append(
                Transaction.description.ilike(like)
                | Transaction.merchant_name.ilike(like)
                | Transaction.reference_number.ilike(like)
                | func.array_to_string(Transaction.tags, " ").ilike(like)
                | func.cast(Transaction.amount, String).ilike(like)
            )
        if type:
            if type == "expense":
                filters.append(
                    or_(
                        Transaction.type == "expense",
                        Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]),
                    )
                )
            else:
                filters.append(Transaction.type == type)
        if category_id:
            filters.append(Transaction.category_id == category_id)
        if account_id:
            filters.append(Transaction.account_id == account_id)
        if account_source:
            source = account_source.lower()
            if source == "cash":
                filters.append(func.lower(Account.type) == "cash")
            elif source == "bank":
                filters.append(func.lower(Account.type).in_(["bank", "mobile_banking"]))
            elif source == "card":
                filters.append(func.lower(Account.type).in_(["card", "credit_card", "debit_card"]))
        if from_date:
            filters.append(Transaction.txn_date >= from_date)
        if to_date:
            filters.append(Transaction.txn_date < to_date + timedelta(days=1))
        if merchant:
            filters.append(Transaction.merchant_name.ilike(f"%{merchant}%"))
        if tags:
            filters.append(Transaction.tags.overlap(tags))
        if recurring_only:
            filters.append(Transaction.is_recurring.is_(True))
        if transfer_only:
            filters.append(Transaction.type == "transfer")
        if min_amount is not None:
            filters.append(Transaction.amount >= min_amount)
        if max_amount is not None:
            filters.append(Transaction.amount <= max_amount)

        base_stmt = select(Transaction)
        count_stmt = select(func.count()).select_from(Transaction)
        if account_source:
            base_stmt = base_stmt.join(Account, Account.id == Transaction.account_id)
            count_stmt = count_stmt.join(Account, Account.id == Transaction.account_id)

        stmt = base_stmt.where(*filters).order_by(Transaction.txn_date.desc(), Transaction.id.desc()).limit(limit).offset(offset)
        items = list((await self.db.execute(stmt)).scalars().all())
        total = await self.db.scalar(count_stmt.where(*filters))
        return items, int(total or 0)

    async def update(self, user_id: UUID, transaction_id: UUID, payload: TransactionUpdate):
        trx = await self.db.get(Transaction, transaction_id)
        if not trx or trx.user_id != user_id:
            return None
        try:
            old_from = await self._get_account(user_id, trx.account_id)
            old_to = await self._get_account(user_id, trx.transfer_account_id) if trx.type == "transfer" else None
            await self._reverse_balance(old_from, old_to, trx)
            for field, value in payload.model_dump(exclude_unset=True).items():
                setattr(trx, field, value)
            if trx.transaction_type is None:
                trx.transaction_type = trx.type
            trx.transaction_date = trx.txn_date
            new_from = await self._get_account(user_id, trx.account_id)
            new_to = await self._get_account(user_id, trx.transfer_account_id) if trx.type == "transfer" else None
            self._normalize_transfer_type(new_from, new_to, trx)
            await self._apply_balance(new_from, new_to, trx)
            await self.db.commit()
            await self.db.refresh(trx)
            return trx
        except Exception:
            await self.db.rollback()
            raise

    async def delete(self, user_id: UUID, transaction_id: UUID):
        trx = await self.db.get(Transaction, transaction_id)
        if not trx or trx.user_id != user_id:
            return False
        try:
            from_acc = await self._get_account(user_id, trx.account_id)
            to_acc = await self._get_account(user_id, trx.transfer_account_id) if trx.type == "transfer" else None
            await self._reverse_balance(from_acc, to_acc, trx)
            await self.db.delete(trx)
            await self.db.commit()
            return True
        except Exception:
            await self.db.rollback()
            raise

    async def bulk_update(self, user_id: UUID, payload: BulkTransactionUpdate) -> int:
        rows = list((await self.db.execute(select(Transaction).where(Transaction.user_id == user_id, Transaction.id.in_(payload.ids)))).scalars())
        data = payload.model_dump(exclude={"ids"}, exclude_unset=True)
        for trx in rows:
            for field, value in data.items():
                setattr(trx, field, value)
        await self.db.commit()
        return len(rows)

    async def bulk_delete(self, user_id: UUID, ids: list[UUID]) -> int:
        count = 0
        for trx_id in ids:
            if await self.delete(user_id, trx_id):
                count += 1
        return count

    async def split(self, user_id: UUID, payload: SplitTransactionCreate):
        total = sum((item.amount for item in payload.splits), Decimal("0"))
        if total != payload.parent.amount:
            raise HTTPException(400, "Split totals must equal parent amount")
        try:
            parent = await self._build_and_apply(user_id, payload.parent)
            parent.is_split = True
            children = []
            for item in payload.splits:
                child = Transaction(
                    user_id=user_id,
                    account_id=payload.parent.account_id,
                    category_id=item.category_id,
                    type=payload.parent.type,
                    transaction_type=payload.parent.type,
                    payment_method=payload.parent.payment_method,
                    amount=item.amount,
                    txn_date=payload.parent.txn_date,
                    transaction_date=payload.parent.txn_date,
                    description=item.description,
                    merchant_name=item.merchant_name or payload.parent.merchant_name,
                    tags=item.tags,
                    parent_transaction_id=parent.id,
                    transaction_status=payload.parent.transaction_status,
                )
                self.db.add(child)
                children.append(child)
            await self.db.commit()
            await self.db.refresh(parent)
            return {"parent": parent, "children": children}
        except Exception:
            await self.db.rollback()
            raise

    async def analytics(self, user_id: UUID, from_date: Optional[date] = None, to_date: Optional[date] = None):
        filters = [Transaction.user_id == user_id, Transaction.transaction_status == "posted"]
        if from_date:
            filters.append(Transaction.txn_date >= from_date)
        if to_date:
            filters.append(Transaction.txn_date < to_date + timedelta(days=1))
        income = await self.db.scalar(select(func.coalesce(func.sum(Transaction.amount), 0)).where(*filters, Transaction.type == "income"))
        expense_filter = or_(
            Transaction.type == "expense",
            Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]),
        )
        expense = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                *filters,
                expense_filter,
                Transaction.parent_transaction_id.is_(None),
            )
        )
        days = max(((to_date or date.today()) - (from_date or date.today().replace(day=1))).days + 1, 1)
        merchants = (await self.db.execute(
            select(Transaction.merchant_name.label("label"), func.sum(Transaction.amount).label("amount"))
            .where(*filters, expense_filter, Transaction.merchant_name.is_not(None))
            .group_by(Transaction.merchant_name).order_by(func.sum(Transaction.amount).desc()).limit(8)
        )).mappings().all()
        effective_type = case(
            (Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]), "expense"),
            else_=Transaction.type,
        )
        trend = (await self.db.execute(
            select(func.date(Transaction.txn_date).label("date"), effective_type.label("type"), func.sum(Transaction.amount).label("amount"))
            .where(
                *filters,
                or_(
                    Transaction.type.in_(["income", "expense"]),
                    Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]),
                ),
            )
            .group_by(func.date(Transaction.txn_date), effective_type).order_by(func.date(Transaction.txn_date))
        )).mappings().all()
        account_bucket = case(
            (func.lower(Account.type).in_(["cash"]), "Cash"),
            (func.lower(Account.type).in_(["bank", "mobile_banking"]), "Bank"),
            (func.lower(Account.type).in_(["card", "credit_card", "debit_card"]), "Card"),
            else_="Other",
        )
        account_breakdown = (await self.db.execute(
            select(account_bucket.label("label"), func.sum(Transaction.amount).label("amount"))
            .join(Account, Account.id == Transaction.account_id)
            .where(
                *filters,
                expense_filter,
                Transaction.parent_transaction_id.is_(None),
            )
            .group_by(account_bucket)
            .order_by(func.sum(Transaction.amount).desc())
        )).mappings().all()
        return {
            "total_income": income or Decimal("0"),
            "total_expense": expense or Decimal("0"),
            "net_cashflow": (income or Decimal("0")) - (expense or Decimal("0")),
            "average_daily_spending": (expense or Decimal("0")) / Decimal(days),
            "top_categories": [],
            "top_merchants": [dict(r) for r in merchants],
            "income_vs_expense": [{"label": "Income", "amount": income or 0}, {"label": "Expense", "amount": expense or 0}],
            "spending_trend": [dict(r) for r in trend],
            "expense_heatmap": [dict(r) for r in trend if r["type"] == "expense"],
            "account_breakdown": [dict(r) for r in account_breakdown],
        }

    async def _apply_balance(self, from_acc: Account, to_acc: Optional[Account], trx):
        if trx.type == "expense":
            if is_credit_card(from_acc):
                from_acc.current_outstanding += trx.amount
            elif from_acc.balance < trx.amount:
                raise HTTPException(400, "Insufficient balance")
            else:
                from_acc.balance -= trx.amount
        elif trx.type == "income":
            from_acc.balance += trx.amount
        elif trx.type == "transfer":
            if not to_acc:
                raise HTTPException(400, "Transfer account required")
            is_card_spending = is_credit_card(from_acc) and getattr(trx, "transaction_type", None) == "CARD_SPENDING"
            if is_card_spending:
                from_acc.current_outstanding += trx.amount
            else:
                if not is_credit_card(from_acc) and from_acc.balance < trx.amount:
                    raise HTTPException(400, "Insufficient balance")
                from_acc.balance -= trx.amount
            if is_credit_card(to_acc) and getattr(trx, "transaction_type", None) == "CARD_PAYMENT":
                to_acc.current_outstanding = max(to_acc.current_outstanding - trx.amount, ZERO)
            else:
                to_acc.balance += trx.amount
        self._after_balance_change(from_acc, to_acc)

    async def _reverse_balance(self, from_acc: Account, to_acc: Optional[Account], trx):
        if trx.type == "expense":
            if is_credit_card(from_acc):
                from_acc.current_outstanding = max(from_acc.current_outstanding - trx.amount, ZERO)
            else:
                from_acc.balance += trx.amount
        elif trx.type == "income":
            from_acc.balance -= trx.amount
        elif trx.type == "transfer" and to_acc:
            if is_credit_card(from_acc) and getattr(trx, "transaction_type", None) == "CARD_SPENDING":
                from_acc.current_outstanding = max(from_acc.current_outstanding - trx.amount, ZERO)
            else:
                from_acc.balance += trx.amount
            if is_credit_card(to_acc) and getattr(trx, "transaction_type", None) == "CARD_PAYMENT":
                to_acc.current_outstanding += trx.amount
            else:
                to_acc.balance -= trx.amount
        self._after_balance_change(from_acc, to_acc)

    async def _get_account(self, user_id: UUID, account_id: UUID) -> Account:
        acc = (await self.db.execute(
            select(Account).options(selectinload(Account.credit_card_details)).where(Account.id == account_id)
        )).scalar_one_or_none()
        if not acc or acc.user_id != user_id:
            raise HTTPException(404, "Account not found")
        return acc

    async def _build_and_apply(self, user_id: UUID, payload: TransactionCreate) -> Transaction:
        from_acc = await self._get_account(user_id, payload.account_id)
        to_acc = await self._get_account(user_id, payload.transfer_account_id) if payload.type == "transfer" else None
        transaction_type = payload.transaction_type or payload.type
        if payload.type == "transfer" and to_acc and is_credit_card(to_acc) and not is_credit_card(from_acc):
            transaction_type = "CARD_PAYMENT"
            payload.transaction_type = transaction_type
        elif payload.type == "transfer" and to_acc and is_credit_card(from_acc) and not is_credit_card(to_acc):
            transaction_type = "CARD_SPENDING"
            payload.transaction_type = transaction_type
        await self._apply_balance(from_acc, to_acc, payload)
        trx = Transaction(
            user_id=user_id,
            account_id=payload.account_id,
            transfer_account_id=payload.transfer_account_id,
            category_id=payload.category_id,
            type=payload.type,
            transaction_type=transaction_type,
            payment_method=payload.payment_method,
            amount=payload.amount,
            txn_date=payload.txn_date,
            transaction_date=payload.txn_date,
            is_emergency=payload.is_emergency,
            description=payload.description,
            merchant_name=payload.merchant_name,
            tags=payload.tags,
            location=payload.location,
            attachment_url=payload.attachment_url,
            recurring_rule=payload.recurring_rule,
            is_recurring=payload.is_recurring,
            transaction_status=payload.transaction_status,
            reference_number=payload.reference_number,
        )
        self.db.add(trx)
        await self.db.flush()
        return trx

    def _normalize_transfer_type(self, from_acc: Account, to_acc: Optional[Account], trx) -> None:
        if trx.type != "transfer" or not to_acc:
            return
        if is_credit_card(to_acc) and not is_credit_card(from_acc):
            trx.transaction_type = "CARD_PAYMENT"
        elif is_credit_card(from_acc) and not is_credit_card(to_acc):
            trx.transaction_type = "CARD_SPENDING"
        elif trx.transaction_type in ("CARD_PAYMENT", "CARD_SPENDING"):
            trx.transaction_type = "transfer"

    def _after_balance_change(self, from_acc: Account, to_acc: Optional[Account]) -> None:
        for account in [from_acc, to_acc]:
            if not account:
                continue
            details = getattr(account, "credit_card_details", None)
            if is_credit_card(account) and details:
                details.credit_limit = account.credit_limit or details.credit_limit
                details.statement_day = account.billing_cycle_day
                details.due_day = account.payment_due_day
                details.available_credit = max(details.credit_limit - account.current_outstanding, Decimal("0"))
            self.db.add(AccountBalanceHistory(account_id=account.id, balance_date=datetime.now(UTC), closing_balance=account.balance))
