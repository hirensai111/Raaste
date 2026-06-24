from fastapi import APIRouter

from app.api.v1.endpoints import auth, destinations, trips, companion, profile, reviews

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["auth"])
api_router.include_router(
    destinations.router, prefix="/destinations", tags=["destinations"]
)
api_router.include_router(trips.router, prefix="/trips", tags=["trips"])
api_router.include_router(companion.router, prefix="/companion", tags=["companion"])
api_router.include_router(profile.router, prefix="/profile", tags=["profile"])
api_router.include_router(reviews.router, prefix="/reviews", tags=["reviews"])
