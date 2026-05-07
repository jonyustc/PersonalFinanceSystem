from app.api.v1.endpoints import monthly_income
from fastapi import APIRouter

from app.api.v1.endpoints import (
    accounts,
    auth,
    budgets,
    cards,
    categories,
    dashboard,
    notifications,
    reports,
    transactions,
    transfers,
    users,
    card,
)

api_router = APIRouter()

# 🔹 Auth & User
api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(users.router, prefix="/users", tags=["users"])

# 🔹 Core Modules
api_router.include_router(
    accounts.router, prefix="/accounts", tags=["accounts"])
api_router.include_router(
    categories.router, prefix="/categories", tags=["categories"])
api_router.include_router(
    transactions.router, prefix="/transactions", tags=["transactions"])
api_router.include_router(card.router, prefix="/card", tags=["card"])
api_router.include_router(transfers.router, prefix="/transfers", tags=["transfers"])
api_router.include_router(cards.router, prefix="/cards", tags=["cards"])

# 🔹 Budget & Reports
api_router.include_router(budgets.router, prefix="/budgets", tags=["budgets"])
api_router.include_router(
    dashboard.router, prefix="/dashboard", tags=["dashboard"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])

# 🔹 Notifications
api_router.include_router(notifications.router,
                          prefix="/notifications", tags=["notifications"])


api_router.include_router(
    monthly_income.router,
    prefix="/budgets",
    tags=["Budgets"],
)
