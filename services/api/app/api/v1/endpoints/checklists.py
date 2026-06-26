from fastapi import APIRouter, Depends, Header, HTTPException, status

from app.config import settings
from app.dependencies import get_current_user
from app.schemas.checklist import (
    ChecklistResponse,
    ChecklistRunRequest,
    ChecklistRunResponse,
)
from app.schemas.common import APIResponse
from app.services.checklist_service import ChecklistService

router = APIRouter()


@router.get("/trips/{trip_id}", response_model=APIResponse[list[ChecklistResponse]])
def list_trip_checklists(
    trip_id: str,
    current_user: dict = Depends(get_current_user),
):
    checklists = ChecklistService().list_trip_checklists(
        trip_id=trip_id,
        user_id=current_user.get("sub") or "",
    )
    return APIResponse(data=checklists)


@router.post("/cron/run-due", response_model=APIResponse[ChecklistRunResponse])
async def run_due_checklists(
    request: ChecklistRunRequest,
    x_cron_secret: str | None = Header(default=None, alias="X-Cron-Secret"),
):
    if settings.cron_secret and x_cron_secret != settings.cron_secret:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid cron secret",
        )

    result = await ChecklistService().run_due_checklists(run_date=request.run_date)
    return APIResponse(data=result)
