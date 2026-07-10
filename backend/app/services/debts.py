from __future__ import annotations

from decimal import Decimal
from uuid import UUID

from sqlalchemy import case, func, select
from sqlalchemy.dialects.postgresql import aggregate_order_by
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.transaction import Transaction
from app.schemas.debts import DebtPartySummary, DebtSummaryResponse


ZERO = Decimal("0")


def _sum_for(debt_type: str):
    return func.coalesce(
        func.sum(case((Transaction.debt_type == debt_type, Transaction.amount), else_=ZERO)),
        ZERO,
    )


class DebtsService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def summary(self, user_id: UUID) -> DebtSummaryResponse:
        # Most recent spelling of the counterparty name within each
        # case-insensitive group.
        display_name = func.array_agg(
            aggregate_order_by(
                Transaction.counterparty_name,
                Transaction.txn_date.desc(),
                Transaction.id.desc(),
            )
        )[1]
        stmt = (
            select(
                display_name.label("counterparty"),
                _sum_for("lent").label("total_lent"),
                _sum_for("borrowed").label("total_borrowed"),
                _sum_for("repaid_by_them").label("total_repaid_by_them"),
                _sum_for("repaid_to_them").label("total_repaid_to_them"),
                func.count().label("txn_count"),
                func.max(Transaction.txn_date).label("last_txn_date"),
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.debt_type.is_not(None),
                Transaction.counterparty_name.is_not(None),
            )
            .group_by(func.lower(Transaction.counterparty_name))
        )
        rows = (await self.db.execute(stmt)).mappings().all()

        parties: list[DebtPartySummary] = []
        total_receivable = ZERO
        total_payable = ZERO
        for row in rows:
            net = (
                row["total_lent"]
                + row["total_repaid_to_them"]
                - row["total_borrowed"]
                - row["total_repaid_by_them"]
            )
            if net > ZERO:
                direction = "they_owe_me"
                total_receivable += net
            elif net < ZERO:
                direction = "i_owe_them"
                total_payable += -net
            else:
                direction = "settled"
            parties.append(
                DebtPartySummary(
                    counterparty=row["counterparty"],
                    net_amount=float(net),
                    direction=direction,
                    total_lent=float(row["total_lent"]),
                    total_borrowed=float(row["total_borrowed"]),
                    total_repaid_by_them=float(row["total_repaid_by_them"]),
                    total_repaid_to_them=float(row["total_repaid_to_them"]),
                    txn_count=int(row["txn_count"]),
                    last_txn_date=row["last_txn_date"],
                )
            )

        parties.sort(key=lambda p: (p.direction == "settled", -abs(p.net_amount)))
        return DebtSummaryResponse(
            total_receivable=float(total_receivable),
            total_payable=float(total_payable),
            parties=parties,
        )
