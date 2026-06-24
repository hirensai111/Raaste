from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from app.dependencies import get_db_session
from app.schemas.destination import DestinationListItem, DestinationResponse
from app.schemas.common import APIResponse
from app.services.destination_service import DestinationService

router = APIRouter()


@router.get("", response_model=APIResponse[list[DestinationListItem]])
def list_destinations(
    q: str | None = Query(None, description="Search by destination name or state"),
    db: Session = Depends(get_db_session),
):
    destinations = DestinationService(db).list_destinations(query=q)
    return APIResponse(
        data=[DestinationListItem.model_validate(d) for d in destinations]
    )


@router.get("/{slug}", response_model=APIResponse[DestinationResponse])
def get_destination(
    slug: str,
    db: Session = Depends(get_db_session),
):
    destination = DestinationService(db).get_destination_by_slug(slug)
    return APIResponse(data=DestinationResponse.model_validate(destination))
