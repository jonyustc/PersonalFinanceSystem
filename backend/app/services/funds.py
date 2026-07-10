# app/services/fund.py

from uuid import UUID
from decimal import Decimal
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from fastapi import HTTPException, status

from app.models.account import Account
from app.models.transaction import Transaction

# Convention: fund member is stored in transaction tags
# "fund:mine"   → you spent from the fund
# "fund:friend" → friend spent from the fund
FUND_TAG_MINE = "fund:mine"
FUND_TAG_FRIEND = "fund:friend"
FUND_SUBTYPE = "fund"


class FundService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_summary(self, user_id: UUID, account_id: UUID) -> dict:
        # Verify ownership and subtype
        account = await self._get_fund_account(user_id, account_id)

        # All expense transactions on this account
        txns_result = await self.db.execute(
            select(Transaction)
            .where(
                Transaction.user_id == user_id,
                Transaction.account_id == account_id,
                Transaction.type == "expense",
            )
            .order_by(Transaction.txn_date.desc())
        )
        txns = txns_result.scalars().all()

        my_spent = Decimal("0")
        friend_spent = Decimal("0")
        untagged_spent = Decimal("0")

        for t in txns:
            tags = t.tags or []
            amount = t.amount
            if FUND_TAG_MINE in tags:
                my_spent += amount
            elif FUND_TAG_FRIEND in tags:
                friend_spent += amount
            else:
                untagged_spent += amount

        total_spent = my_spent + friend_spent + untagged_spent
        outstanding_amount = my_spent - friend_spent
        fund_balance = account.balance  # tracked by transaction engine

        # Contributions: sum of all income into this account
        contrib_result = await self.db.scalar(
            select(func.coalesce(func.sum(Transaction.amount), 0)).where(
                Transaction.user_id == user_id,
                Transaction.account_id == account_id,
                Transaction.type == "income",
            )
        )
        total_contributed = Decimal(str(contrib_result or 0))

        # Percent breakdown
        def pct(part: Decimal, total: Decimal) -> float:
            if total <= 0:
                return 0.0
            return round(float(part / total * 100), 1)

        return {
            "account_id": str(account_id),
            "account_name": account.name,
            "currency": account.currency,
            "fund_balance": float(fund_balance),
            "total_contributed": float(total_contributed),
            "total_spent": float(total_spent),
            "outstanding_amount": float(outstanding_amount),
            "my_spent": float(my_spent),
            "friend_spent": float(friend_spent),
            "untagged_spent": float(untagged_spent),
            "my_spent_pct": pct(my_spent, total_spent),
            "friend_spent_pct": pct(friend_spent, total_spent),
            "untagged_pct": pct(untagged_spent, total_spent),
            "recent_transactions": [
                {
                    "id": str(t.id),
                    "amount": float(t.amount),
                    "type": t.type,
                    "txn_date": t.txn_date.isoformat(),
                    "description": t.description,
                    "merchant_name": t.merchant_name,
                    "tags": t.tags or [],
                    "category_id": str(t.category_id) if t.category_id else None,
                    "member": (
                        "mine" if FUND_TAG_MINE in (t.tags or [])
                        else "friend" if FUND_TAG_FRIEND in (t.tags or [])
                        else "untagged"
                    ),
                }
                for t in txns[:20]
            ],
        }

    async def get_transactions(self, user_id: UUID, account_id: UUID) -> dict:
        await self._get_fund_account(user_id, account_id)

        result = await self.db.execute(
            select(Transaction)
            .where(
                Transaction.user_id == user_id,
                Transaction.account_id == account_id,
            )
            .order_by(Transaction.txn_date.desc())
        )
        txns = result.scalars().all()

        mine = []
        friend = []
        untagged = []

        for t in txns:
            tags = t.tags or []
            row = {
                "id": str(t.id),
                "amount": float(t.amount),
                "type": t.type,
                "txn_date": t.txn_date.isoformat(),
                "description": t.description,
                "merchant_name": t.merchant_name,
                "tags": tags,
                "category_id": str(t.category_id) if t.category_id else None,
            }
            if t.type == "expense":
                if FUND_TAG_MINE in tags:
                    mine.append(row)
                elif FUND_TAG_FRIEND in tags:
                    friend.append(row)
                else:
                    untagged.append(row)

        return {
            "mine": mine,
            "friend": friend,
            "untagged": untagged,
        }

    async def _get_fund_account(self, user_id: UUID, account_id: UUID) -> Account:
        result = await self.db.execute(
            select(Account).where(
                Account.id == account_id,
                Account.user_id == user_id,
            )
        )
        account = result.scalar_one_or_none()
        if not account:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="Account not found",
            )
        if account.account_subtype != FUND_SUBTYPE:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Account is not a fund account. Set account_subtype='fund' when creating.",
            )
        return account
