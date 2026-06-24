from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.user import UserProfile


class TripCreateRequest(BaseModel):
    destination_id: UUID
    days: int = Field(ge=1, le=30)
    profile: UserProfile


class TripResponse(BaseModel):
    id: UUID
    user_id: UUID | None = None
    destination_id: UUID
    days: int
    traveller_profile: dict
    itinerary: list[dict]
    checklist: list[dict]
    status: str

    model_config = ConfigDict(from_attributes=True)
