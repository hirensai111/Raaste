from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.dependencies import get_db_session, get_current_user
from app.schemas.user import UserResponse, UserProfileUpdate
from app.schemas.common import APIResponse
from app.services.user_service import UserService

router = APIRouter()


@router.get("/me", response_model=APIResponse[UserResponse])
def get_me(
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    user = UserService(db).get_user(current_user.get("sub"))
    return APIResponse(data=UserResponse.model_validate(user))


@router.put("/me", response_model=APIResponse[UserResponse])
def update_me(
    data: UserProfileUpdate,
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    user = UserService(db).update_user(current_user.get("sub"), data)
    return APIResponse(data=UserResponse.model_validate(user))
