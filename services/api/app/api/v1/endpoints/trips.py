from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.dependencies import get_db_session, get_current_user
from app.schemas.trip import TripCreateRequest, TripResponse
from app.schemas.common import APIResponse
from app.services.trip_service import TripService

router = APIRouter()


@router.post("", response_model=APIResponse[TripResponse])
def create_trip(
    request: TripCreateRequest,
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    trip = TripService(db).create_trip(request, current_user.get("sub"))
    return APIResponse(data=TripResponse.model_validate(trip))


@router.get("/{trip_id}", response_model=APIResponse[TripResponse])
def get_trip(
    trip_id: str,
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    trip = TripService(db).get_trip(trip_id, current_user.get("sub"))
    return APIResponse(data=TripResponse.model_validate(trip))
