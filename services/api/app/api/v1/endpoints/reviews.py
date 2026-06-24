from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.dependencies import get_db_session, get_current_user
from app.schemas.review import ReviewCreate, ReviewResponse
from app.schemas.common import APIResponse
from app.models.review import Review

router = APIRouter()


@router.post("", response_model=APIResponse[ReviewResponse])
def create_review(
    data: ReviewCreate,
    db: Session = Depends(get_db_session),
    current_user: dict = Depends(get_current_user),
):
    review = Review(
        trip_id=data.trip_id,
        user_id=current_user.get("sub"),
        destination_id=data.destination_id,
        what_was_great=data.what_was_great,
        what_was_disappointing=data.what_was_disappointing,
        what_is_outdated=data.what_is_outdated,
        rating=data.rating,
    )
    db.add(review)
    db.commit()
    db.refresh(review)
    return APIResponse(data=ReviewResponse.model_validate(review))
