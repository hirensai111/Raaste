import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, Integer, DateTime, JSON, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Trip(Base):
    __tablename__ = "trips"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    destination_id = Column(
        UUID(as_uuid=True), ForeignKey("destinations.id"), nullable=False
    )
    days = Column(Integer, nullable=False)
    traveller_profile = Column(JSON, default=dict)
    itinerary = Column(JSON, default=list)
    checklist = Column(JSON, default=list)
    status = Column(String, default="planned")  # planned, active, completed
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
