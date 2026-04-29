from uuid import UUID

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.v1.deps import get_current_user
from app.db.session import get_db
from app.models.user import User
from app.schemas.category import CategoryCreate, CategoryResponse, CategoryUpdate
from app.services.category import CategoryService

router = APIRouter()


@router.post("", response_model=CategoryResponse, status_code=status.HTTP_201_CREATED)
async def create_category(payload: CategoryCreate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).create(current_user.id, payload)


@router.get("", response_model=list[CategoryResponse])
async def list_categories(current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).list(current_user.id)


@router.get("/{category_id}", response_model=CategoryResponse)
async def get_category(category_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).get(current_user.id, category_id)


@router.patch("/{category_id}", response_model=CategoryResponse)
async def update_category(category_id: UUID, payload: CategoryUpdate, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    return await CategoryService(db).update(current_user.id, category_id, payload)


@router.delete("/{category_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_category(category_id: UUID, current_user: User = Depends(get_current_user), db: AsyncSession = Depends(get_db)):
    await CategoryService(db).delete(current_user.id, category_id)
