from uuid import UUID

from sqlalchemy import select

from app.models.category import Category
from app.repositories.base import BaseRepository


class CategoryRepository(BaseRepository[Category]):
    model = Category

    async def list_by_user(self, user_id: UUID) -> list[Category]:
        result = await self.db.execute(select(Category).where(Category.user_id == user_id).order_by(Category.type, Category.name))
        return list(result.scalars())

    async def get_user_owned(self, user_id: UUID, category_id: UUID) -> Category | None:
        result = await self.db.execute(select(Category).where(Category.id == category_id, Category.user_id == user_id))
        return result.scalar_one_or_none()
