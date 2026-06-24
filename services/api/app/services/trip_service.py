from sqlalchemy.orm import Session

from app.models.trip import Trip
from app.models.destination import Destination
from app.schemas.trip import TripCreateRequest
from app.services.destination_service import DestinationService
from app.core.exceptions import NotFoundException


class TripService:
    def __init__(self, db: Session):
        self.db = db
        self.destination_service = DestinationService(db)

    def create_trip(self, request: TripCreateRequest, user_id: str | None) -> Trip:
        destination = self.destination_service.get_destination(
            str(request.destination_id)
        )

        itinerary = self._generate_itinerary(destination, request.days)
        checklist = self._generate_checklist(destination)

        trip = Trip(
            user_id=user_id,
            destination_id=destination.id,
            days=request.days,
            traveller_profile=request.profile.model_dump(),
            itinerary=itinerary,
            checklist=checklist,
            status="planned",
        )
        self.db.add(trip)
        self.db.commit()
        self.db.refresh(trip)
        return trip

    def get_trip(self, trip_id: str, user_id: str | None = None) -> Trip:
        trip = self.db.query(Trip).filter(Trip.id == trip_id).first()
        if not trip:
            raise NotFoundException(f"Trip '{trip_id}' not found")
        return trip

    def _generate_itinerary(self, destination: Destination, days: int) -> list[dict]:
        # TODO: Replace with AI + rules engine
        return [
            {
                "day": day,
                "title": f"Day {day} in {destination.name}",
                "activities": [
                    {"time": "Morning", "activity": "Explore local area"},
                    {"time": "Afternoon", "activity": "Visit a popular spot"},
                    {"time": "Evening", "activity": "Try local food"},
                ],
            }
            for day in range(1, days + 1)
        ]

    def _generate_checklist(self, destination: Destination) -> list[dict]:
        return [
            {"category": "Documents", "items": ["ID proof", "Hotel bookings"]},
            {"category": "Essentials", "items": ["Power bank", "Cash"]},
        ]
