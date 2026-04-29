from datetime import datetime
from decimal import Decimal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field


class ORMModel(BaseModel):
    model_config = ConfigDict(from_attributes=True)


class Timestamped(ORMModel):
    id: UUID
    created_at: datetime
    updated_at: datetime


class PaginatedResponse(BaseModel):
    total: int
    limit: int
    offset: int
    items: list


Money = Field(max_digits=14, decimal_places=2, ge=Decimal("0"))
