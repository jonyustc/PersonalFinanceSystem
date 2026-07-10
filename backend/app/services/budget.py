from datetime import datetime, timedelta
from decimal import Decimal

from fastapi import HTTPException
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models.budget import Budget
from app.models.category import Category
from app.models.monthly_income import MonthlyIncome
from app.models.transaction import Transaction


class BudgetService:
    def __init__(self, db: AsyncSession):
        self.db = db

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

    async def update_budget(self, user_id: str, budget_id: str, data):
        budget = await self.db.get(Budget, budget_id)
        if not budget or budget.user_id != user_id:
            raise HTTPException(404, "Budget not found")

        budget.amount = data.amount
        await self.db.commit()
        await self.db.refresh(budget)
        return budget

    async def delete_budget(self, user_id: str, budget_id: str):
        budget = await self.db.get(Budget, budget_id)
        if not budget or budget.user_id != user_id:
            raise HTTPException(404, "Budget not found")

        await self.db.delete(budget)
        await self.db.commit()

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

    async def get_budget_summary(self, user_id: str, month: str):
        start_date = datetime.strptime(month + "-01", "%Y-%m-%d")
        end_date = (start_date + timedelta(days=32)).replace(day=1)
        report_expense_filter = or_(
            Transaction.type == "expense",
            Transaction.transaction_type.in_(["CARD_PAYMENT", "CARD_SPENDING"]),
        )

        Parent = aliased(Category)
        Child = aliased(Category)

        child_spent_sub = (
            select(
                Child.parent_id.label("parent_id"),
                func.sum(Transaction.amount).label("spent"),
            )
            .join(Child, Child.id == Transaction.category_id)
            .where(
                Transaction.user_id == user_id,
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
                Transaction.include_in_totals.is_(True),
                report_expense_filter,
            )
            .group_by(Child.parent_id)
            .subquery()
        )

        direct_spent_sub = (
            select(
                Transaction.category_id.label("category_id"),
                func.sum(Transaction.amount).label("spent"),
            )
            .where(
                Transaction.user_id == user_id,
                Transaction.txn_date >= start_date,
                Transaction.txn_date < end_date,
                Transaction.include_in_totals.is_(True),
                report_expense_filter,
            )
            .group_by(Transaction.category_id)
            .subquery()
        )

        query = (
            select(
                Parent.id.label("category_id"),
                Parent.name.label("category_name"),
                Budget.amount.label("budget"),
                (
                    func.coalesce(child_spent_sub.c.spent, 0)
                    + func.coalesce(direct_spent_sub.c.spent, 0)
                ).label("spent"),
            )
            .join(Parent, Budget.category_id == Parent.id)
            .outerjoin(child_spent_sub, child_spent_sub.c.parent_id == Parent.id)
            .outerjoin(direct_spent_sub, direct_spent_sub.c.category_id == Parent.id)
            .where(
                Budget.user_id == user_id,
                Budget.month == month,
                func.lower(Parent.type) == "expense",
            )
            .order_by(Parent.name)
        )

        result = await self.db.execute(query)
        categories = []
        total_budget = Decimal("0")
        total_spent = Decimal("0")

        for row in result:
            budget = Decimal(row.budget or 0)
            spent = Decimal(row.spent or 0)
            total_budget += budget
            total_spent += spent
            categories.append(
                {
                    "category_id": str(row.category_id),
                    "category_name": row.category_name,
                    "budget": float(budget),
                    "spent": float(spent),
                    "remaining": float(budget - spent),
                    "used_percentage": float((spent / budget) * 100) if budget > 0 else 0,
                    "overspending": spent > budget,
                }
            )

        monthly_income = await self.db.scalar(
            select(MonthlyIncome).where(
                MonthlyIncome.user_id == user_id,
                MonthlyIncome.month == month,
            )
        )
        income = Decimal(monthly_income.amount if monthly_income else 0)
        opening_balance = Decimal(monthly_income.opening_balance if monthly_income else 0)
        total_balance = income + opening_balance

        return {
            "month": month,
            "income": float(income),
            "opening_balance": float(opening_balance),
            "total_balance": float(total_balance),
            "total_budget": float(total_budget),
            "total_spent": float(total_spent),
            "planned_balance": float(total_balance - total_budget),
            "actual_balance": float(total_balance - total_spent),
            "categories": categories,
        }

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
