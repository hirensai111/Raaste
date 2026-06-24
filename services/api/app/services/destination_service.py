from sqlalchemy.orm import Session

from app.models.destination import Destination
from app.schemas.destination import DestinationResponse
from app.core.exceptions import NotFoundException


class DestinationService:
    def __init__(self, db: Session):
        self.db = db

    def list_destinations(self, query: str | None = None) -> list[Destination]:
        q = self.db.query(Destination)
        if query:
            q = q.filter(
                Destination.name.ilike(f"%{query}%")
                | Destination.state.ilike(f"%{query}%")
            )
        return q.all()

    def get_destination_by_slug(self, slug: str) -> Destination:
        destination = self.db.query(Destination).filter(Destination.slug == slug).first()
        if not destination:
            raise NotFoundException(f"Destination '{slug}' not found")
        return destination

    def get_destination(self, destination_id: str) -> Destination:
        destination = (
            self.db.query(Destination).filter(Destination.id == destination_id).first()
        )
        if not destination:
            raise NotFoundException(f"Destination '{destination_id}' not found")
        return destination
