from datetime import UTC, datetime
from decimal import Decimal
import logging
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account, AccountBalanceHistory, AccountTransfer, CreditCardDetails
from app.models.transaction import Transaction
from app.repositories.account import AccountRepository
from app.schemas.account import (
    AccountAnalyticsResponse,
    AccountCreate,
    AccountSummaryResponse,
    AccountUpdate,
    BalanceAdjustmentCreate,
    CardSummaryResponse,
    TransferCreate,
)
from app.services.funds import FUND_SUBTYPE, FUND_TAG_FRIEND, FUND_TAG_MINE


ZERO = Decimal("0")
logger = logging.getLogger("app.accounts")
CREDIT_CARD_TYPES = {"card", "credit_card"}
CARD_TYPES = CREDIT_CARD_TYPES | {"debit_card"}


def normalize_account_type(account_type: str) -> str:
    value = account_type.lower()
    if value == "mobile_banking":
        return "mobile_banking"
    if value == "debit_card":
        return "debit_card"
    if value == "credit_card":
        return "credit_card"
    return value


def is_credit_card(account: Account) -> bool:
    return account.type.lower() in CREDIT_CARD_TYPES


def is_card_account(account: Account) -> bool:
    return account.type.lower() in CARD_TYPES


class AccountService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.accounts = AccountRepository(db)

    async def create(self, user_id: UUID, payload: AccountCreate) -> Account:
        try:
            # Idempotent create for replayed offline pushes: a client-supplied id
            # that already exists returns the stored account untouched.
            if payload.id is not None:
                existing = await self.db.get(Account, payload.id)
                if existing is not None:
                    if existing.user_id != user_id:
                        raise HTTPException(409, "Account id already exists")
                    return existing
            data = payload.model_dump(exclude={"card_details"})
            if data.get("id") is None:
                data.pop("id", None)
            opening_balance = data["opening_balance"]
            data["user_id"] = user_id
            data["type"] = normalize_account_type(data["type"])
            data["balance"] = opening_balance
            data["currency"] = data["currency"].upper()
            if data["type"] in CREDIT_CARD_TYPES:
                if data.get("credit_limit") is None and payload.card_details:
                    data["credit_limit"] = payload.card_details.credit_limit
                opening_available = max(opening_balance, ZERO)
                opening_outstanding = max((data.get("credit_limit") or ZERO) - opening_available, ZERO)
                data["balance"] = ZERO
                data["current_outstanding"] = max(data.get("current_outstanding") or opening_outstanding, ZERO)
                if data.get("billing_cycle_day") is None and payload.card_details:
                    data["billing_cycle_day"] = payload.card_details.statement_day
                if data.get("payment_due_day") is None and payload.card_details:
                    data["payment_due_day"] = payload.card_details.due_day

            account = await self.accounts.create(data)

            if is_credit_card(account):
                details_payload = (
                    payload.card_details.model_dump()
                    if payload.card_details
                    else {
                        "credit_limit": account.credit_limit or ZERO,
                        "statement_day": account.billing_cycle_day,
                        "due_day": account.payment_due_day,
                        "minimum_payment_percent": ZERO,
                        "annual_fee": ZERO,
                        "interest_rate": ZERO,
                        "auto_pay_enabled": False,
                    }
                )
                details_payload["credit_limit"] = account.credit_limit or details_payload["credit_limit"]
                details_payload["statement_day"] = account.billing_cycle_day or details_payload["statement_day"]
                details_payload["due_day"] = account.payment_due_day or details_payload["due_day"]
                details = CreditCardDetails(
                    account_id=account.id, **details_payload)
                details.available_credit = self._available_credit(
                    account.current_outstanding, details.credit_limit)
                await self.accounts.create_card_details(details)

            await self._record_balance(account)
            await self.db.commit()
            await self.db.refresh(account)
            return await self.get(user_id, account.id)
        except HTTPException:
            await self.db.rollback()
            logger.warning("account_create_validation_failed", extra={
                           "user_id": str(user_id), "account_type": payload.type})
            raise
        except Exception:
            await self.db.rollback()
            logger.exception("account_create_failed", extra={
                             "user_id": str(user_id), "account_type": payload.type})
            raise

    async def list(self, user_id: UUID, active_only: bool = True) -> list[Account]:
        accounts = await self.accounts.list_by_user(user_id)
        if active_only:
            return [account for account in accounts if account.is_active and not account.archived]
        return accounts

    async def get(self, user_id: UUID, account_id: UUID) -> Account:
        account = await self.accounts.get_user_owned(user_id, account_id)
        if not account:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
        return account

    async def update(self, user_id: UUID, account_id: UUID, payload: AccountUpdate) -> Account:
        account = await self.get(user_id, account_id)
        data = payload.model_dump(exclude_unset=True, exclude={"card_details"})
        opening_balance_updated = "opening_balance" in data
        previous_opening_balance = account.opening_balance or ZERO
        opening_balance_changed = (
            opening_balance_updated
            and (data.get("opening_balance") or ZERO) != previous_opening_balance
        )
        previous_type = account.type

        for field, value in data.items():
            if field == "currency" and value:
                value = value.upper()
            if field == "type" and value:
                value = normalize_account_type(value)
            setattr(account, field, value)

        if opening_balance_changed:
            opening_balance = account.opening_balance or ZERO
            if is_credit_card(account):
                opening_available = max(opening_balance, ZERO)
                account.balance = ZERO
                account.current_outstanding = max(
                    (account.credit_limit or ZERO) - opening_available,
                    ZERO,
                )
            elif previous_type.lower() not in CREDIT_CARD_TYPES:
                if opening_balance < ZERO:
                    raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Only card accounts may have a negative opening balance")
                account.balance = (account.balance or ZERO) + (opening_balance - previous_opening_balance)

        if payload.card_details is not None:
            if not is_credit_card(account):
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                    detail="Card details require a card account")
            details = account.credit_card_details or CreditCardDetails(
                account_id=account.id)
            for field, value in payload.card_details.model_dump().items():
                setattr(details, field, value)
            account.credit_limit = details.credit_limit
            account.billing_cycle_day = details.statement_day
            account.payment_due_day = details.due_day
            details.available_credit = self._available_credit(
                account.current_outstanding, details.credit_limit)
            if not account.credit_card_details:
                await self.accounts.create_card_details(details)

        if account.credit_card_details:
            if opening_balance_changed and is_credit_card(account):
                opening_available = max(account.opening_balance or ZERO, ZERO)
                account.current_outstanding = max((account.credit_limit or ZERO) - opening_available, ZERO)
            account.credit_limit = account.credit_limit if account.credit_limit is not None else account.credit_card_details.credit_limit
            account.billing_cycle_day = account.billing_cycle_day or account.credit_card_details.statement_day
            account.payment_due_day = account.payment_due_day or account.credit_card_details.due_day
            account.credit_card_details.credit_limit = account.credit_limit or ZERO
            account.credit_card_details.statement_day = account.billing_cycle_day
            account.credit_card_details.due_day = account.payment_due_day
            account.credit_card_details.available_credit = self._available_credit(
                account.current_outstanding,
                account.credit_limit,
            )

        await self.db.commit()
        await self.db.refresh(account)
        return await self.get(user_id, account_id)

    async def delete(self, user_id: UUID, account_id: UUID) -> None:
        account = await self.get(user_id, account_id)
        transaction_count = await self.db.scalar(
            select(func.count())
            .select_from(Transaction)
            .where(
                Transaction.user_id == user_id,
                or_(
                    Transaction.account_id == account_id,
                    Transaction.transfer_account_id == account_id,
                ),
            )
        )
        if transaction_count:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete an account that has transactions",
            )

        effective_balance = account.current_outstanding if is_credit_card(account) else account.balance
        if effective_balance != ZERO:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Cannot delete an account with a non-zero balance",
            )

        account.is_active = False
        account.archived = True
        await self.db.commit()

    async def summary(self, user_id: UUID) -> AccountSummaryResponse:
        accounts = await self.list(user_id)
        cash_balance = sum(
            (a.balance for a in accounts if a.type == "cash" and not a.archived), ZERO)
        total_assets = sum((a.balance for a in accounts if a.type !=
                           "card" and not is_credit_card(a) and a.balance > ZERO and not a.archived), ZERO)
        card_debt = sum((a.current_outstanding for a in accounts if is_credit_card(a) and not a.archived), ZERO)
        liabilities = card_debt + \
            sum((abs(a.balance) for a in accounts if a.type !=
                "card" and not is_credit_card(a) and a.balance < ZERO and not a.archived), ZERO)
        credit_used = sum((self._card_utilization_amount(
            a) for a in accounts if is_credit_card(a) and not a.archived), ZERO)
        return AccountSummaryResponse(
            total_assets=total_assets,
            liabilities=liabilities,
            net_worth=total_assets - liabilities,
            card_debt=card_debt,
            cash_balance=cash_balance,
            credit_used=credit_used,
        )

    async def analytics(self, user_id: UUID) -> AccountAnalyticsResponse:
        accounts = [account for account in await self.list(user_id) if not account.archived]
        distribution = []
        for account_type in ("cash", "bank", "mobile_banking", "debit_card", "credit_card"):
            typed = [
                account for account in accounts if account.type == account_type]
            distribution.append(
                {"type": account_type, "total": sum(
                    (account.balance for account in typed), ZERO), "count": len(typed)}
            )

        summary = await self.summary(user_id)
        net_worth_trend = await self.net_worth_trend(user_id)
        balance_trend = [{"date": point.date, "balance": point.net_worth}
                         for point in net_worth_trend]
        return AccountAnalyticsResponse(
            distribution=distribution,
            debt_vs_assets=[
                {"label": "Assets", "amount": summary.total_assets},
                {"label": "Liabilities", "amount": summary.liabilities},
            ],
            balance_trend=balance_trend,
            net_worth_trend=[point.model_dump() for point in net_worth_trend],
        )

    async def net_worth_trend(self, user_id: UUID):
        from app.schemas.account import NetWorthTrendPoint

        rows = await self.accounts.balance_history_since(user_id)
        if not rows:
            summary = await self.summary(user_id)
            return [NetWorthTrendPoint(date=datetime.now(UTC).date().isoformat(), net_worth=summary.net_worth)]
        return [NetWorthTrendPoint(date=row_date.isoformat(), net_worth=net_worth) for row_date, net_worth in rows]

    async def transfer(self, user_id: UUID, payload: TransferCreate) -> AccountTransfer:
        try:
            from_account = await self.get(user_id, payload.from_account_id)
            to_account = await self.get(user_id, payload.to_account_id)
            amount = payload.amount
            fee = payload.fee
            card_spending_amount = amount + fee
            is_card_spending_transfer = is_credit_card(from_account) and not is_credit_card(to_account)

            if is_card_spending_transfer:
                from_account.current_outstanding += card_spending_amount
            else:
                self._ensure_can_debit(from_account, card_spending_amount)
                from_account.balance -= card_spending_amount
            if is_credit_card(to_account) and payload.is_card_payment:
                to_account.current_outstanding = max(to_account.current_outstanding - amount, ZERO)
            else:
                to_account.balance += amount

            self._refresh_card_credit(from_account)
            self._refresh_card_credit(to_account)

            transfer = AccountTransfer(
                user_id=user_id,
                from_account_id=from_account.id,
                to_account_id=to_account.id,
                amount=amount,
                fee=fee,
                notes=payload.notes,
                transfer_date=payload.transfer_date or datetime.now(UTC),
            )
            await self.accounts.create_transfer(transfer)

            if is_credit_card(to_account) and payload.is_card_payment:
                card_payment = Transaction(
                    user_id=user_id,
                    account_id=from_account.id,
                    transfer_account_id=to_account.id,
                    type="transfer",
                    transaction_type="CARD_PAYMENT",
                    amount=amount,
                    txn_date=transfer.transfer_date,
                    transaction_date=transfer.transfer_date,
                    description=payload.notes or f"Card payment to {to_account.name}",
                    transfer_id=transfer.id,
                )
                self.db.add(card_payment)

            if is_card_spending_transfer:
                card_spending = Transaction(
                    user_id=user_id,
                    account_id=from_account.id,
                    transfer_account_id=to_account.id,
                    type="transfer",
                    transaction_type="CARD_SPENDING",
                    amount=card_spending_amount,
                    txn_date=transfer.transfer_date,
                    transaction_date=transfer.transfer_date,
                    description=payload.notes or f"Card spending to {to_account.name}",
                    transfer_id=transfer.id,
                )
                self.db.add(card_spending)

            if from_account.account_subtype == FUND_SUBTYPE:
                fund_transfer_tag = (
                    FUND_TAG_FRIEND
                    if to_account.account_subtype != FUND_SUBTYPE
                    else FUND_TAG_MINE
                )
                transfer_expense = Transaction(
                    user_id=user_id,
                    account_id=from_account.id,
                    transfer_account_id=to_account.id,
                    type="expense",
                    transaction_type="expense",
                    amount=amount + fee,
                    txn_date=transfer.transfer_date,
                    transaction_date=transfer.transfer_date,
                    description=payload.notes or f"Transfer to {to_account.name}",
                    tags=[fund_transfer_tag],
                    transfer_id=transfer.id,
                )
                self.db.add(transfer_expense)

            if to_account.account_subtype == FUND_SUBTYPE:
                transfer_income = Transaction(
                    user_id=user_id,
                    account_id=to_account.id,
                    transfer_account_id=from_account.id,
                    type="income",
                    transaction_type="income",
                    amount=amount,
                    txn_date=transfer.transfer_date,
                    transaction_date=transfer.transfer_date,
                    description=payload.notes or f"Transfer from {from_account.name}",
                    transfer_id=transfer.id,
                )
                self.db.add(transfer_income)

            await self._record_balance(from_account)
            await self._record_balance(to_account)
            await self.db.commit()
        except HTTPException:
            await self.db.rollback()
            logger.warning(
                "account_transfer_validation_failed",
                extra={
                    "user_id": str(user_id),
                    "from_account_id": str(payload.from_account_id),
                    "to_account_id": str(payload.to_account_id),
                },
            )
            raise
        except Exception:
            await self.db.rollback()
            logger.exception(
                "account_transfer_failed",
                extra={
                    "user_id": str(user_id),
                    "from_account_id": str(payload.from_account_id),
                    "to_account_id": str(payload.to_account_id),
                },
            )
            raise

        await self.db.refresh(transfer)
        return transfer

    async def adjust_balance(self, user_id: UUID, account_id: UUID, payload: BalanceAdjustmentCreate) -> Account:
        account = await self.get(user_id, account_id)
        if not is_credit_card(account) and payload.closing_balance < ZERO:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Non-card accounts cannot be adjusted below zero")

        if is_credit_card(account):
            account.current_outstanding = max(payload.closing_balance, ZERO)
        else:
            account.balance = payload.closing_balance
        self._refresh_card_credit(account)
        await self._record_balance(account)
        await self.db.commit()
        await self.db.refresh(account)
        return await self.get(user_id, account_id)

    async def card_summary(self, user_id: UUID, account_id: UUID) -> CardSummaryResponse:
        account = await self.get(user_id, account_id)
        if not is_credit_card(account) or not account.credit_card_details:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="Card account details not found")

        details = account.credit_card_details
        utilization = self._card_utilization(account)
        return CardSummaryResponse(
            account_id=account.id,
            account_name=account.name,
            balance=account.balance,
            credit_limit=details.credit_limit,
            available_credit=self._available_credit(
                account.current_outstanding, details.credit_limit),
            utilization=utilization,
            statement_day=details.statement_day,
            due_day=details.due_day,
            minimum_payment_percent=details.minimum_payment_percent,
            minimum_payment_due=(account.current_outstanding * details.minimum_payment_percent / Decimal("100")),
            auto_pay_enabled=details.auto_pay_enabled,
        )

    async def _record_balance(self, account: Account) -> None:
        await self.accounts.create_balance_history(
            AccountBalanceHistory(
                account_id=account.id,
                balance_date=datetime.now(UTC),
                closing_balance=account.current_outstanding if is_credit_card(account) else account.balance,
            )
        )

    def _refresh_card_credit(self, account: Account) -> None:
        if is_credit_card(account) and account.credit_card_details:
            account.credit_card_details.available_credit = self._available_credit(
                account.current_outstanding,
                account.credit_limit or account.credit_card_details.credit_limit,
            )
            account.credit_card_details.credit_limit = account.credit_limit or account.credit_card_details.credit_limit
            account.credit_card_details.statement_day = account.billing_cycle_day
            account.credit_card_details.due_day = account.payment_due_day

    def _ensure_can_debit(self, account: Account, amount: Decimal) -> None:
        if not is_credit_card(account) and account.balance - amount < ZERO:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST,
                                detail="Insufficient funds for this transfer")

    def _available_credit(self, outstanding: Decimal, credit_limit: Decimal | None) -> Decimal:
        used = outstanding or ZERO
        credit_limit = credit_limit or ZERO
        return max(credit_limit - used, ZERO)

    def _card_utilization(self, account: Account) -> Decimal:
        details = account.credit_card_details
        limit = account.credit_limit or (details.credit_limit if details else ZERO)
        if not details or limit <= ZERO:
            return ZERO
        return account.current_outstanding / limit * Decimal("100")

    def _card_utilization_amount(self, account: Account) -> Decimal:
        details = account.credit_card_details
        limit = account.credit_limit or (details.credit_limit if details else ZERO)
        if limit <= ZERO:
            return ZERO
        return self._card_utilization(account)
