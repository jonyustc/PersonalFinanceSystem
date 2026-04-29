from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.category import Category
from app.repositories.category import CategoryRepository
from app.schemas.category import CategoryCreate, CategoryUpdate


class CategoryService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.categories = CategoryRepository(db)

    async def create(self, user_id: UUID, payload: CategoryCreate) -> Category:
        category = await self.categories.create({"user_id": user_id, **payload.model_dump()})
        await self.db.commit()
        return category

    async def list(self, user_id: UUID) -> list[Category]:
        return await self.categories.list_by_user(user_id)

    async def get(self, user_id: UUID, category_id: UUID) -> Category:
        category = await self.categories.get_user_owned(user_id, category_id)
        if not category:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Category not found")
        return category

    async def update(self, user_id: UUID, category_id: UUID, payload: CategoryUpdate) -> Category:
        category = await self.get(user_id, category_id)
        for field, value in payload.model_dump(exclude_unset=True).items():
            setattr(category, field, value)
        await self.db.commit()
        await self.db.refresh(category)
        return category

    async def delete(self, user_id: UUID, category_id: UUID) -> None:
        category = await self.get(user_id, category_id)
        await self.categories.delete(category)
        await self.db.commit()
