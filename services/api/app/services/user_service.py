from sqlalchemy.orm import Session

from app.models.user import User
from app.schemas.user import UserCreate, UserProfileUpdate
from app.core.exceptions import NotFoundException


class UserService:
    def __init__(self, db: Session):
        self.db = db

    def create_or_update_user(self, data: UserCreate) -> User:
        user = None
        if data.phone:
            user = self.db.query(User).filter(User.phone == data.phone).first()
        elif data.email:
            user = self.db.query(User).filter(User.email == data.email).first()

        if user:
            if data.name:
                user.name = data.name
            if data.profile:
                user.dietary_preferences = data.profile.dietary_preferences
                user.travel_style = data.profile.travel_style
                user.travel_companion = data.profile.travel_companion
                user.interests = data.profile.interests
                user.budget_min = data.profile.budget_min
                user.budget_max = data.profile.budget_max
        else:
            user = User(
                phone=data.phone,
                email=data.email,
                name=data.name,
                dietary_preferences=data.profile.dietary_preferences,
                travel_style=data.profile.travel_style,
                travel_companion=data.profile.travel_companion,
                interests=data.profile.interests,
                budget_min=data.profile.budget_min,
                budget_max=data.profile.budget_max,
            )
            self.db.add(user)

        self.db.commit()
        self.db.refresh(user)
        return user

    def get_user(self, user_id: str) -> User:
        user = self.db.query(User).filter(User.id == user_id).first()
        if not user:
            raise NotFoundException(f"User '{user_id}' not found")
        return user

    def update_user(self, user_id: str, data: UserProfileUpdate) -> User:
        user = self.get_user(user_id)
        if data.name:
            user.name = data.name
        if data.profile:
            user.dietary_preferences = data.profile.dietary_preferences
            user.travel_style = data.profile.travel_style
            user.travel_companion = data.profile.travel_companion
            user.interests = data.profile.interests
            user.budget_min = data.profile.budget_min
            user.budget_max = data.profile.budget_max
        self.db.commit()
        self.db.refresh(user)
        return user
