from datetime import datetime
from typing import Literal, Optional

from pydantic import BaseModel


DebtDirection = Literal["they_owe_me", "i_owe_them", "settled"]


class DebtPartySummary(BaseModel):
    counterparty: str
    net_amount: float
    direction: DebtDirection
    total_lent: float
    total_borrowed: float
    total_repaid_by_them: float
    total_repaid_to_them: float
    txn_count: int
    last_txn_date: Optional[datetime] = None


class DebtSummaryResponse(BaseModel):
    total_receivable: float
    total_payable: float
    parties: list[DebtPartySummary]
