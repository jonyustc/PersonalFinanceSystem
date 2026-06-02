# app/api/v1/endpoints/budget.py

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from typing import List

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.budget import BudgetCreate, BudgetUpdate, BudgetResponse, BudgetSummaryResponse
from app.services.budget import BudgetService

router = APIRouter()


# =========================
# GET (FETCH BY MONTH)
# =========================
@router.get("", response_model=List[BudgetResponse])
async def get_budgets(
    month: str = Query(..., example="2026-05"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    return await service.get_budgets(current_user.id, month)


# =========================
# CREATE
# =========================
@router.post("", response_model=BudgetResponse)
@router.post("/", response_model=BudgetResponse)
async def create_budget(
    payload: BudgetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    return await service.create_budget(current_user.id, payload)


# =========================
# UPDATE (PATCH - CONSISTENT)
# =========================
@router.patch("/{budget_id}", response_model=BudgetResponse)
async def update_budget(
    budget_id: str,
    payload: BudgetUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    return await service.update_budget(current_user.id, budget_id, payload)


@router.delete("/{budget_id}")
async def delete_budget(
    budget_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    await service.delete_budget(current_user.id, budget_id)
    return {"success": True}


# =========================
# UPSERT (🔥 BEST FOR FRONTEND)
# =========================
@router.post("/upsert", response_model=BudgetResponse)
async def upsert_budget(
    payload: BudgetCreate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    return await service.upsert_budget(current_user.id, payload)


# =========================
# ✅ BUDGET SUMMARY (FIX)
# =========================
@router.get("/summary", response_model=BudgetSummaryResponse)
async def get_budget_summary(
    month: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = BudgetService(db)
    return await service.get_budget_summary(current_user.id, month)
