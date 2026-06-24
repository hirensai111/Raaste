from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.dependencies import get_db_session
from app.schemas.user import UserCreate, UserResponse
from app.schemas.common import APIResponse
from app.services.user_service import UserService

router = APIRouter()


@router.post("/otp/send")
async def send_otp(phone: str):
    # TODO: Integrate with SMS provider
    return APIResponse(data={"message": "OTP sent", "phone": phone})


@router.post("/otp/verify")
async def verify_otp(phone: str, otp: str):
    # TODO: Verify OTP and return JWT
    return APIResponse(data={"token": "dummy-token", "phone": phone})


@router.post("/profile", response_model=APIResponse[UserResponse])
def create_profile(
    data: UserCreate,
    db: Session = Depends(get_db_session),
):
    user = UserService(db).create_or_update_user(data)
    return APIResponse(data=UserResponse.model_validate(user))
