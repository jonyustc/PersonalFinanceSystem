# app/services/budget.py

from sqlalchemy import select, func, and_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased
from fastapi import HTTPException
from datetime import datetime, timedelta

from app.models.budget import Budget
from app.models.transaction import Transaction
from app.models.category import Category


class BudgetService:
    def __init__(self, db: AsyncSession):
        self.db = db

    # =========================
    # CREATE
    # =========================
    async def create_budget(self, user_id: str, data):
        existing = await self.db.scalar(
            select(Budget).where(
                Budget.user_id == user_id,
                Budget.category_id == data.category_id,
                Budget.month == data.month,
            )
        )

        if existing:
            raise HTTPException(400, "Budget already exists")

        budget = Budget(
            user_id=user_id,
            category_id=data.category_id,
            amount=data.amount,
            month=data.month,
        )

        self.db.add(budget)
        await self.db.commit()
        await self.db.refresh(budget)

        return budget

    # =========================
    # UPDATE
    # =========================
    async def update_budget(self, user_id: str, budget_id: str, data):
        budget = await self.db.get(Budget, budget_id)

        if not budget or budget.user_id != user_id:
            raise HTTPException(404, "Budget not found")

        budget.amount = data.amount

        await self.db.commit()
        await self.db.refresh(budget)

        return budget

    # =========================
    # UPSERT
    # =========================
    async def upsert_budget(self, user_id: str, data):
        budget = await self.db.scalar(
            select(Budget).where(
                Budget.user_id == user_id,
                Budget.category_id == data.category_id,
                Budget.month == data.month,
            )
        )

        if budget:
            budget.amount = data.amount
        else:
            budget = Budget(
                user_id=user_id,
                category_id=data.category_id,
                amount=data.amount,
                month=data.month,
            )
            self.db.add(budget)

        await self.db.commit()
        await self.db.refresh(budget)

        return budget

    # =========================
    # ✅ FIXED: Budget vs Actual (parent_id based)
    # =========================
    async def get_budget_summary(self, user_id: str, month: str):
        start_date = datetime.strptime(month + "-01", "%Y-%m-%d")
        end_date = (start_date + timedelta(days=32)).replace(day=1)

        Parent = aliased(Category)   # Needs / Wants
        Child = aliased(Category)    # Food / Rent

        # 🔥 Subquery to avoid duplication
        tx_sub = (
            select(
                Child.parent_id.label("parent_id"),
                func.sum(Transaction.amount).label("spent"),
            )
            .join(Child, Child.id == Transaction.category_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
                Transaction.type == "expense",
            )
            .group_by(Child.parent_id)
            .subquery()
        )

        query = (
            select(
                Parent.id.label("category_id"),
                Parent.name.label("category_name"),
                Budget.amount.label("budget"),
                func.coalesce(tx_sub.c.spent, 0).label("spent"),
            )
            .join(Parent, Budget.category_id == Parent.id)
            .outerjoin(tx_sub, tx_sub.c.parent_id == Parent.id)
            .where(
                Budget.user_id == user_id,
                Budget.month == month,
            )
        )

        result = await self.db.execute(query)

        categories = [
            {
                "category_id": str(r.category_id),
                "category_name": r.category_name,
                "budget": float(r.budget),
                "spent": float(r.spent),
            }
            for r in result
        ]

        return {
            "month": month,
            "income": 0,
            "categories": categories,
        }

    # =========================
    # GET BUDGET LIST
    # =========================
    async def get_budgets(self, user_id: str, month: str):
        result = await self.db.execute(
            select(Budget).where(
                Budget.user_id == user_id,
                Budget.month == month,
            )
        )

        budgets = result.scalars().all()

        return [
            {
                "id": str(b.id),
                "category_id": str(b.category_id),
                "amount": float(b.amount),
                "month": b.month,
            }
            for b in budgets
        ]
