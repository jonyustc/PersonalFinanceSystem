from uuid import UUID
from typing import Literal, List, Optional
from pydantic import BaseModel, Field

CategoryType = Literal["expense", "income"]


class CategoryCreate(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: CategoryType
    parent_id: Optional[UUID] = None
    color: Optional[str] = None
    icon: Optional[str] = None


class CategoryUpdate(BaseModel):
    name: Optional[str] = Field(default=None, min_length=1, max_length=120)
    type: Optional[CategoryType] = None
    parent_id: Optional[UUID] = None
    color: Optional[str] = None
    icon: Optional[str] = None


class CategoryResponse(BaseModel):
    id: UUID
    name: str
    type: str
    parent_id: Optional[UUID]
    color: Optional[str]
    icon: Optional[str]

    # ✅ KEEP children
    children: List["CategoryResponse"] = []

    class Config:
        from_attributes = True


CategoryResponse.model_rebuild()
