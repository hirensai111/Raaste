from uuid import UUID
from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field


class ReviewCreate(BaseModel):
    trip_id: UUID
    destination_id: UUID
    what_was_great: str | None = Field(None, max_length=2000)
    what_was_disappointing: str | None = Field(None, max_length=2000)
    what_is_outdated: str | None = Field(None, max_length=2000)
    rating: int | None = Field(None, ge=1, le=5)


class ReviewResponse(BaseModel):
    id: UUID
    trip_id: UUID
    user_id: UUID | None = None
    destination_id: UUID
    what_was_great: str | None = None
    what_was_disappointing: str | None = None
    what_is_outdated: str | None = None
    rating: int | None = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)
