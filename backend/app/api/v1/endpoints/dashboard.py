from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.services.dashboard import DashboardService

router = APIRouter()


# =========================
# MAIN DASHBOARD ENDPOINT (RECOMMENDED)
# =========================
@router.get("", tags=["Dashboard"])
async def dashboard(
    month: str | None = Query(None, example="2026-05"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Unified dashboard endpoint
    """

    # ✅ Default month (important)
    if not month:
        month = datetime.now().strftime("%Y-%m")

    service = DashboardService(db)

    return await service.get_full_summary(
        user_id=current_user.id,
        month=month,
    )


# =========================
# OPTIONAL: EXPLICIT FULL SUMMARY ENDPOINT
# =========================
@router.get("/full-summary", tags=["Dashboard"])
async def get_full_summary(
    month: str = Query(..., example="2026-05"),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Explicit full summary endpoint (optional)
    """

    service = DashboardService(db)

    return await service.get_full_summary(
        user_id=current_user.id,
        month=month,
    )


@router.get("/cards", tags=["Dashboard"])
async def card_dashboard(
    month: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = DashboardService(db)
    return await service.get_card_dashboard(current_user.id, month)


@router.get("/card-analytics", tags=["Dashboard"])
async def card_analytics(
    month: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    service = DashboardService(db)
    return await service.get_card_analytics(current_user.id, month)
