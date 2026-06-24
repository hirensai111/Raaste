from app.schemas.user import UserCreate, UserResponse, UserProfileUpdate
from app.schemas.destination import DestinationResponse, DestinationListItem
from app.schemas.trip import TripCreateRequest, TripResponse
from app.schemas.companion import CompanionRequest, CompanionResponse
from app.schemas.review import ReviewCreate, ReviewResponse
from app.schemas.common import APIResponse

__all__ = [
    "UserCreate",
    "UserResponse",
    "UserProfileUpdate",
    "DestinationResponse",
    "DestinationListItem",
    "TripCreateRequest",
    "TripResponse",
    "CompanionRequest",
    "CompanionResponse",
    "ReviewCreate",
    "ReviewResponse",
    "APIResponse",
]
