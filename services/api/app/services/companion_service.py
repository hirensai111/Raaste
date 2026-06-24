from sqlalchemy.orm import Session

from app.schemas.companion import CompanionRequest
from app.services.ai_service import AIService
from app.services.destination_service import DestinationService
from app.services.trip_service import TripService
from app.core.constants import PRICE_DISCLAIMER


COMPANION_SYSTEM_PROMPT = """You are Raaste, a well-travelled local friend for Indian domestic travellers.
You give short, practical, judgmental answers. You know about transport, food, costs, crowds, safety, and hidden spots.
Always mention if prices may have changed. Never recommend non-veg or Jain-incompatible places to users with those dietary preferences.
Keep answers concise and actionable.
"""


class CompanionService:
    def __init__(self, db: Session):
        self.db = db
        self.ai = AIService()
        self.destination_service = DestinationService(db)
        self.trip_service = TripService(db)

    async def answer(self, request: CompanionRequest, user_id: str | None) -> dict:
        context_parts = []

        if request.trip_id:
            trip = self.trip_service.get_trip(str(request.trip_id), user_id)
            destination = self.destination_service.get_destination(
                str(trip.destination_id)
            )
            context_parts.append(f"Destination: {destination.name}, {destination.state}")
            context_parts.append(
                f"Traveller profile: {trip.traveller_profile}"
            )
        elif request.destination_id:
            destination = self.destination_service.get_destination(
                str(request.destination_id)
            )
            context_parts.append(f"Destination: {destination.name}, {destination.state}")

        if request.lat and request.lon:
            context_parts.append(f"Current location: lat={request.lat}, lon={request.lon}")

        context = "\n".join(context_parts)
        user_message = f"{context}\n\nUser question: {request.query}\n\n{PRICE_DISCLAIMER}"

        answer = await self.ai.ask(COMPANION_SYSTEM_PROMPT, user_message)

        return {
            "answer": answer,
            "sources": None,
            "suggested_actions": None,
        }
