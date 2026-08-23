from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    app_env: str = "development"
    database_url: str = "sqlite:///./luohao-assistant.db"
    jwt_secret: str = "change-me"
    app_password: str = "change-me"
    deepseek_api_key: str | None = None
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_chat_model: str = "deepseek-chat"
    deepseek_reasoner_model: str = "deepseek-reasoner"
    cors_origins: str = "http://localhost:3000"
    jwt_expiry_days: int = 7

    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    @model_validator(mode="after")
    def validate_runtime(self) -> "Settings":
        if self.app_env.lower() == "production":
            if len(self.jwt_secret) < 32 or self.jwt_secret in {"change-me", "replace-with-a-long-random-secret"}:
                raise ValueError("JWT_SECRET must be a random value of at least 32 characters in production")
            if not self.app_password.startswith("$argon2"):
                raise ValueError("APP_PASSWORD must be an Argon2 hash in production")
            if self.database_url.startswith("sqlite"):
                raise ValueError("DATABASE_URL must use PostgreSQL in production")
            if not self.deepseek_api_key:
                raise ValueError("DEEPSEEK_API_KEY is required in production")
        return self

    @property
    def cors_origin_list(self) -> list[str]:
        return [item.strip() for item in self.cors_origins.split(",") if item.strip()]


@lru_cache
def get_settings() -> Settings:
    return Settings()
