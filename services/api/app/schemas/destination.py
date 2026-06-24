from uuid import UUID

from pydantic import BaseModel, ConfigDict


class DestinationListItem(BaseModel):
    id: UUID
    slug: str
    name: str
    state: str
    tagline: str | None = None
    tags: list[str]

    model_config = ConfigDict(from_attributes=True)


class DestinationResponse(BaseModel):
    id: UUID
    slug: str
    name: str
    state: str
    tagline: str | None = None
    description: str | None = None
    tags: list[str]
    best_time_to_visit: str | None = None
    how_to_reach: dict | None = None
    local_transport: dict | None = None
    approximate_costs: dict | None = None
    customs_and_tips: list[str] | None = None
    safety_info: str | None = None
    latitude: float | None = None
    longitude: float | None = None

    model_config = ConfigDict(from_attributes=True)
