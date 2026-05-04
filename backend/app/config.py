"""Application settings loaded from environment variables.

Pydantic Settings is the single source of truth for env-derived configuration.
All other modules read settings via `get_settings()` rather than calling `os.environ` directly.
"""

from __future__ import annotations

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Typed settings loaded from environment + optional .env file."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    database_url: str
    """SQLAlchemy async URL, e.g. postgresql+asyncpg://user:pass@host:5432/db"""

    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"] = "INFO"
    """Logging verbosity for the structlog root logger."""

    app_version: str = "0.1.0"
    """Reported by /health. Bump on release."""


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached accessor — env is read once per process."""
    return Settings()
