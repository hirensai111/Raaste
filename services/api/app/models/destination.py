import uuid
from datetime import datetime, timezone

from sqlalchemy import Column, String, Text, JSON, DateTime, Float
from sqlalchemy.dialects.postgresql import UUID

from app.database import Base


class Destination(Base):
    __tablename__ = "destinations"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    slug = Column(String, unique=True, nullable=False, index=True)
    name = Column(String, nullable=False)
    state = Column(String, nullable=False)
    tagline = Column(String, nullable=True)
    description = Column(Text, nullable=True)
    tags = Column(JSON, default=list)
    best_time_to_visit = Column(String, nullable=True)
    how_to_reach = Column(JSON, default=dict)
    local_transport = Column(JSON, default=dict)
    approximate_costs = Column(JSON, default=dict)
    customs_and_tips = Column(JSON, default=list)
    safety_info = Column(Text, nullable=True)
    latitude = Column(Float, nullable=True)
    longitude = Column(Float, nullable=True)
    created_at = Column(DateTime, default=lambda: datetime.now(timezone.utc))
    updated_at = Column(
        DateTime,
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
    )
