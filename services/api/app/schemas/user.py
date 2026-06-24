from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class UserProfile(BaseModel):
    dietary_preferences: list[str] = Field(default_factory=list)
    travel_style: str | None = None
    travel_companion: str | None = None
    interests: list[str] = Field(default_factory=list)
    budget_min: str | None = None
    budget_max: str | None = None


class UserCreate(BaseModel):
    phone: str | None = None
    email: EmailStr | None = None
    name: str | None = None
    profile: UserProfile = Field(default_factory=UserProfile)


class UserProfileUpdate(BaseModel):
    name: str | None = None
    profile: UserProfile | None = None


class UserResponse(BaseModel):
    id: UUID
    phone: str | None = None
    email: str | None = None
    name: str | None = None
    profile: UserProfile

    model_config = ConfigDict(from_attributes=True)
