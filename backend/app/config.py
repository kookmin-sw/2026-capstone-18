"""Application settings loaded from environment variables.

Pydantic Settings is the single source of truth for env-derived configuration.
All other modules read settings via `get_settings()` rather than calling `os.environ` directly.
"""

from __future__ import annotations

import uuid
from functools import lru_cache
from typing import Literal

from pydantic import Field
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

    app_version: str = "0.4.0"
    """Reported by /health. Bump on release."""

    supabase_url: str
    """Project URL, e.g. https://<project-ref>.supabase.co."""

    supabase_anon_key: str
    """Public anon key. Safe to expose to client builds; treated as a secret here only because it controls API quota."""

    supabase_service_role_key: str
    """Service-role secret. NEVER ship to clients. Used for admin operations (anon-to-Google upgrade)."""

    supabase_jwt_secret: str
    """HS256 secret used to verify Supabase-issued JWTs."""

    google_oauth_client_id: str
    """Google Cloud OAuth client ID. Used as the expected `aud` when verifying Google ID tokens directly."""

    task_id: str = Field(
        default_factory=lambda: f"local-{uuid.uuid4().hex[:8]}",
        description=(
            "Identifier for this ECS task / local process. Used by the "
            "WebSocket connection registry to know which rows it owns."
        ),
    )
    websocket_idle_timeout_seconds: int = 300
    """Connections with no heartbeat for this long are considered stale."""

    firebase_credentials_json: str | None = None
    """JSON-encoded Firebase service account credentials. Injected from
    Secrets Manager in staging/prod. Optional locally — when absent, the
    FCM service short-circuits to a no-op for tests."""


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Cached accessor — env is read once per process."""
    return Settings()
