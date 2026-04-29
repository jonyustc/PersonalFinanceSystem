from typing import Any, Generic, TypeVar
from uuid import UUID

from sqlalchemy import Select, func, select
from sqlalchemy.ext.asyncio import AsyncSession

ModelType = TypeVar("ModelType")


class BaseRepository(Generic[ModelType]):
    model: type[ModelType]

    def __init__(self, db: AsyncSession):
        self.db = db

    async def get(self, obj_id: UUID) -> ModelType | None:
        return await self.db.get(self.model, obj_id)

    async def create(self, data: dict[str, Any]) -> ModelType:
        obj = self.model(**data)
        self.db.add(obj)
        await self.db.flush()
        await self.db.refresh(obj)
        return obj

    async def delete(self, obj: ModelType) -> None:
        await self.db.delete(obj)
        await self.db.flush()

    async def count(self, statement: Select) -> int:
        subquery = statement.order_by(None).subquery()
        result = await self.db.execute(select(func.count()).select_from(subquery))
        return int(result.scalar_one())
