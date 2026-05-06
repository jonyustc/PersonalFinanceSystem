# api/v1/routes/card.py

from uuid import UUID
from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.api.v1.deps import get_current_user
from app.models.user import User
from app.services.transaction import TransactionService
from pydantic import BaseModel


router = APIRouter(prefix="/card", tags=["Card"])


# ✅ Request Schema
class CardPaymentRequest(BaseModel):
    bank_account_id: UUID
    card_account_id: UUID
    amount: Decimal


# ✅ Pay Credit Card
@router.post("/pay")
async def pay_card(
    payload: CardPaymentRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db)
):
    service = TransactionService(db)

    return await service.pay_card(
        user_id=current_user.id,
        bank_id=payload.bank_account_id,
        card_account_id=payload.card_account_id,
        amount=payload.amount
    )
