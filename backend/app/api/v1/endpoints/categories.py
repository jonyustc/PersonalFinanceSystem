from uuid import UUID
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.category import CategoryCreate, CategoryResponse, CategoryUpdate
from app.services.category import CategoryService

router = APIRouter()


@router.post("", response_model=CategoryResponse)
async def create_category(payload: CategoryCreate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).create(user.id, payload)


@router.get("", response_model=list[CategoryResponse])
async def list_categories(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).list(user.id)


@router.patch("/{category_id}", response_model=CategoryResponse)
async def update_category(category_id: UUID, payload: CategoryUpdate, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).update(user.id, category_id, payload)


@router.delete("/{category_id}")
async def delete_category(category_id: UUID, user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await CategoryService(db).delete(user.id, category_id)
    return {"success": True}


@router.get("/tree", response_model=list[CategoryResponse])
async def category_tree(user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).tree(user.id)
