from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.dependencies import get_db_session, get_current_user
from app.schemas.companion import CompanionRequest, CompanionResponse
from app.schemas.common import APIResponse
from app.services.companion_service import CompanionService

router = APIRouter()


@router.post("/ask", response_model=APIResponse[CompanionResponse])
async def ask_companion(
    request: CompanionRequest,
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    result = await CompanionService(db).answer(request, current_user.get("sub"))
    return APIResponse(data=CompanionResponse(**result))
