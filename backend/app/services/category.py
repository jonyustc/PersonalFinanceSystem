from uuid import UUID
from fastapi import HTTPException
from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.category import CategoryRepository
from app.schemas.category import CategoryCreate, CategoryUpdate


class CategoryService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = CategoryRepository(db)

    # =========================
    # HELPER (🔥 KEY FIX)
    # =========================
    def to_dict(self, c):
        return {
            "id": c.id,
            "name": c.name,
            "type": c.type,
            "parent_id": c.parent_id,
            "color": c.color,
            "icon": c.icon,
            "children": [],  # 🔥 IMPORTANT
        }

    # =========================
    # CREATE
    # =========================
    async def create(self, user_id: UUID, payload: CategoryCreate):
        data = payload.model_dump()
        category_id = data.get("id")
        if category_id is None:
            data.pop("id", None)
        else:
            existing = await self.repo.get_user_owned(user_id, category_id)
            if existing:
                return self.to_dict(existing)
        data["user_id"] = user_id
        await self._validate_parent(user_id, data.get("parent_id"), data["type"])

        category = await self.repo.create(data)

        await self.db.commit()
        await self.db.refresh(category)

        # 🔥 RETURN SAFE DICT
        return self.to_dict(category)

    # =========================
    # LIST (FLAT)
    # =========================
    async def list(self, user_id: UUID):
        categories = await self.repo.list_by_user(user_id)
        return [self.to_dict(c) for c in categories]

    # =========================
    # TREE (SAFE VERSION)
    # =========================
    async def tree(self, user_id: UUID):
        categories = await self.repo.list_by_user(user_id)

        items = [self.to_dict(c) for c in categories]

        item_map = {str(item["id"]): item for item in items}

        tree = []

        for item in items:
            if item["parent_id"]:
                parent = item_map.get(str(item["parent_id"]))
                if parent:
                    parent["children"].append(item)
            else:
                tree.append(item)

        return tree

    # =========================
    # GET
    # =========================
    async def get(self, user_id: UUID, category_id: UUID):
        category = await self.repo.get_user_owned(user_id, category_id)

        if not category:
            raise HTTPException(404, "Category not found")

        return self.to_dict(category)

    # =========================
    # UPDATE
    # =========================
    async def update(self, user_id: UUID, category_id: UUID, payload: CategoryUpdate):
        category = await self.repo.get_user_owned(user_id, category_id)

        if not category:
            raise HTTPException(404, "Category not found")

        data = payload.model_dump(exclude_unset=True)
        next_type = data.get("type", category.type)
        if "parent_id" in data:
            if data["parent_id"] == category.id:
                raise HTTPException(400, "Category cannot be its own parent")
            await self._validate_parent(user_id, data["parent_id"], next_type)

        for k, v in data.items():
            setattr(category, k, v)

        await self.db.commit()
        await self.db.refresh(category)

        return self.to_dict(category)

    # =========================
    # DELETE
    # =========================
    async def delete(self, user_id: UUID, category_id: UUID):
        category = await self.repo.get_user_owned(user_id, category_id)

        if not category:
            raise HTTPException(404, "Category not found")

        await self.repo.delete(category)
        await self.db.commit()

    async def _validate_parent(self, user_id: UUID, parent_id: UUID | None, category_type: str):
        if parent_id is None:
            return
        parent = await self.repo.get_user_owned(user_id, parent_id)
        if not parent:
            raise HTTPException(404, "Parent category not found")
        if parent.parent_id is not None:
            raise HTTPException(400, "Subcategories cannot have children")
        if parent.type != category_type:
            raise HTTPException(400, "Parent category type must match")
