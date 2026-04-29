from pydantic import BaseModel, Field

from app.models.category import CategoryType
from app.schemas.common import Timestamped


class CategoryBase(BaseModel):
    name: str = Field(min_length=1, max_length=120)
    type: CategoryType
    color: str | None = Field(default=None, max_length=20)
    icon: str | None = Field(default=None, max_length=80)


class CategoryCreate(CategoryBase):
    pass


class CategoryUpdate(BaseModel):
    name: str | None = Field(default=None, min_length=1, max_length=120)
    type: CategoryType | None = None
    color: str | None = Field(default=None, max_length=20)
    icon: str | None = Field(default=None, max_length=80)


class CategoryResponse(Timestamped):
    name: str
    type: CategoryType
    color: str | None
    icon: str | None
