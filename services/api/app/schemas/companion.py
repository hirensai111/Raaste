from uuid import UUID

from pydantic import BaseModel


class CompanionRequest(BaseModel):
    trip_id: UUID | None = None
    destination_id: UUID | None = None
    query: str
    lat: float | None = None
    lon: float | None = None


class CompanionResponse(BaseModel):
    answer: str
    sources: list[dict] | None = None
    suggested_actions: list[str] | None = None
