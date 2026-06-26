from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    app_name: str = "Raaste API"
    app_env: str = "development"
    debug: bool = True
    secret_key: str = "change-me-in-production"

    host: str = "0.0.0.0"
    port: int = 8000

    database_url: str = "postgresql+psycopg2://postgres:postgres@localhost:5432/raaste"

    supabase_url: str | None = None
    supabase_key: str | None = None
    supabase_service_role_key: str | None = None
    cron_secret: str | None = None

    redis_url: str = "redis://localhost:6379/0"

    openai_api_key: str | None = None
    openai_model: str = "gpt-4o-mini"

    cors_origins: list[str] = ["*"]

    @property
    def is_production(self) -> bool:
        return self.app_env.lower() == "production"


settings = Settings()