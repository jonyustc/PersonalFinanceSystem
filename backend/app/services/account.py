from datetime import UTC, datetime
from decimal import Decimal
import logging
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.account import Account, AccountBalanceHistory, AccountTransfer, CreditCardDetails
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


ZERO = Decimal("0")
logger = logging.getLogger("app.accounts")


class AccountService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.accounts = AccountRepository(db)

    async def create(self, user_id: UUID, payload: AccountCreate) -> Account:
        try:
            data = payload.model_dump(exclude={"card_details"})
            opening_balance = data["opening_balance"]
            data["user_id"] = user_id
            data["balance"] = opening_balance
            data["currency"] = data["currency"].upper()

            account = await self.accounts.create(data)

            if account.type == "card":
                details_payload = (
                    payload.card_details.model_dump()
                    if payload.card_details
                    else {
                        "credit_limit": ZERO,
                        "statement_day": None,
                        "due_day": None,
                        "minimum_payment_percent": ZERO,
                        "annual_fee": ZERO,
                        "interest_rate": ZERO,
                        "auto_pay_enabled": False,
                    }
                )
                details = CreditCardDetails(account_id=account.id, **details_payload)
                details.available_credit = self._available_credit(account.balance, details.credit_limit)
                await self.accounts.create_card_details(details)

            await self._record_balance(account)
            await self.db.commit()
            await self.db.refresh(account)
            return await self.get(user_id, account.id)
        except HTTPException:
            await self.db.rollback()
            logger.warning("account_create_validation_failed", extra={"user_id": str(user_id), "account_type": payload.type})
            raise
        except Exception:
            await self.db.rollback()
            logger.exception("account_create_failed", extra={"user_id": str(user_id), "account_type": payload.type})
            raise

    async def list(self, user_id: UUID) -> list[Account]:
        return await self.accounts.list_by_user(user_id)

    async def get(self, user_id: UUID, account_id: UUID) -> Account:
        account = await self.accounts.get_user_owned(user_id, account_id)
        if not account:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Account not found")
        return account

    async def update(self, user_id: UUID, account_id: UUID, payload: AccountUpdate) -> Account:
        account = await self.get(user_id, account_id)
        data = payload.model_dump(exclude_unset=True, exclude={"card_details"})

        for field, value in data.items():
            if field == "currency" and value:
                value = value.upper()
            setattr(account, field, value)

        if payload.card_details is not None:
            if account.type != "card":
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Card details require a card account")
            details = account.credit_card_details or CreditCardDetails(account_id=account.id)
            for field, value in payload.card_details.model_dump().items():
                setattr(details, field, value)
            details.available_credit = self._available_credit(account.balance, details.credit_limit)
            if not account.credit_card_details:
                await self.accounts.create_card_details(details)

        if account.credit_card_details:
            account.credit_card_details.available_credit = self._available_credit(
                account.balance,
                account.credit_card_details.credit_limit,
            )

        await self.db.commit()
        await self.db.refresh(account)
        return await self.get(user_id, account_id)

    async def delete(self, user_id: UUID, account_id: UUID) -> None:
        account = await self.get(user_id, account_id)
        account.is_active = False
        account.archived = True
        await self.db.commit()

    async def summary(self, user_id: UUID) -> AccountSummaryResponse:
        accounts = await self.list(user_id)
        cash_balance = sum((a.balance for a in accounts if a.type == "cash" and not a.archived), ZERO)
        total_assets = sum((a.balance for a in accounts if a.type != "card" and a.balance > ZERO and not a.archived), ZERO)
        card_debt = sum((abs(a.balance) for a in accounts if a.type == "card" and a.balance < ZERO and not a.archived), ZERO)
        liabilities = card_debt + sum((abs(a.balance) for a in accounts if a.type != "card" and a.balance < ZERO and not a.archived), ZERO)
        credit_used = sum((self._card_utilization_amount(a) for a in accounts if a.type == "card" and not a.archived), ZERO)
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
        for account_type in ("cash", "bank", "card"):
            typed = [account for account in accounts if account.type == account_type]
            distribution.append(
                {"type": account_type, "total": sum((account.balance for account in typed), ZERO), "count": len(typed)}
            )

        summary = await self.summary(user_id)
        net_worth_trend = await self.net_worth_trend(user_id)
        balance_trend = [{"date": point.date, "balance": point.net_worth} for point in net_worth_trend]
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

            self._ensure_can_debit(from_account, amount + fee)
            from_account.balance -= amount + fee
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
        if account.type != "card" and payload.closing_balance < ZERO:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Non-card accounts cannot be adjusted below zero")

        account.balance = payload.closing_balance
        self._refresh_card_credit(account)
        await self._record_balance(account)
        await self.db.commit()
        await self.db.refresh(account)
        return await self.get(user_id, account_id)

    async def card_summary(self, user_id: UUID, account_id: UUID) -> CardSummaryResponse:
        account = await self.get(user_id, account_id)
        if account.type != "card" or not account.credit_card_details:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Card account details not found")

        details = account.credit_card_details
        utilization = self._card_utilization(account)
        return CardSummaryResponse(
            account_id=account.id,
            account_name=account.name,
            balance=account.balance,
            credit_limit=details.credit_limit,
            available_credit=self._available_credit(account.balance, details.credit_limit),
            utilization=utilization,
            statement_day=details.statement_day,
            due_day=details.due_day,
            minimum_payment_percent=details.minimum_payment_percent,
            minimum_payment_due=(abs(account.balance) * details.minimum_payment_percent / Decimal("100")) if account.balance < ZERO else ZERO,
            auto_pay_enabled=details.auto_pay_enabled,
        )

    async def _record_balance(self, account: Account) -> None:
        await self.accounts.create_balance_history(
            AccountBalanceHistory(
                account_id=account.id,
                balance_date=datetime.now(UTC),
                closing_balance=account.balance,
            )
        )

    def _refresh_card_credit(self, account: Account) -> None:
        if account.type == "card" and account.credit_card_details:
            account.credit_card_details.available_credit = self._available_credit(
                account.balance,
                account.credit_card_details.credit_limit,
            )

    def _ensure_can_debit(self, account: Account, amount: Decimal) -> None:
        if account.type != "card" and account.balance - amount < ZERO:
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Insufficient funds for this transfer")

    def _available_credit(self, balance: Decimal, credit_limit: Decimal) -> Decimal:
        used = abs(balance) if balance < ZERO else ZERO
        return max(credit_limit - used, ZERO)

    def _card_utilization(self, account: Account) -> Decimal:
        details = account.credit_card_details
        if not details or details.credit_limit <= ZERO:
            return ZERO
        return (abs(account.balance) / details.credit_limit * Decimal("100")) if account.balance < ZERO else ZERO

    def _card_utilization_amount(self, account: Account) -> Decimal:
        details = account.credit_card_details
        if not details or details.credit_limit <= ZERO:
            return ZERO
        return self._card_utilization(account)
