from datetime import date, datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, Field


class ChecklistResponse(BaseModel):
    id: UUID
    trip_id: UUID
    user_id: UUID
    checklist_type: str
    checklist_date: date
    day_number: int | None = None
    destination_name: str
    trip_dates: str
    content: dict[str, Any]
    generated_at: datetime


class ChecklistRunRequest(BaseModel):
    run_date: date | None = Field(
        default=None,
        description="Optional IST date override for manual backfills/tests.",
    )


class ChecklistRunResponse(BaseModel):
    run_date: date
    scanned_trips: int
    generated: int
    skipped: int
    errors: list[str] = Field(default_factory=list)
