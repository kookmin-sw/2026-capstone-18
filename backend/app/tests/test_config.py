"""Tests for app.config — env-based settings loading."""

from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.config import Settings


def _set_required_supabase_env(monkeypatch: pytest.MonkeyPatch) -> None:
    """Populate the Supabase/Google env vars Settings requires.

    Centralized so existing tests that focus on other fields still satisfy
    the required-field validators introduced in Sprint 3.
    """
    monkeypatch.setenv("SUPABASE_URL", "https://example.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon-key")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "jwt-secret")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "client-id.apps.googleusercontent.com")


def test_settings_loads_from_env(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://u:p@h:5432/db")
    monkeypatch.setenv("LOG_LEVEL", "DEBUG")
    monkeypatch.setenv("APP_VERSION", "0.99.0-test")
    _set_required_supabase_env(monkeypatch)

    settings = Settings(_env_file=None)

    assert settings.database_url == "postgresql+asyncpg://u:p@h:5432/db"
    assert settings.log_level == "DEBUG"
    assert settings.app_version == "0.99.0-test"


def test_settings_log_level_default_is_info(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://u:p@h:5432/db")
    monkeypatch.delenv("LOG_LEVEL", raising=False)
    _set_required_supabase_env(monkeypatch)

    settings = Settings(_env_file=None)

    assert settings.log_level == "INFO"


def test_settings_database_url_required(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    _set_required_supabase_env(monkeypatch)

    with pytest.raises(ValidationError):
        Settings(_env_file=None)


def test_settings_invalid_log_level_rejected(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://u:p@h:5432/db")
    monkeypatch.setenv("LOG_LEVEL", "VERBOSE")
    _set_required_supabase_env(monkeypatch)

    with pytest.raises(ValidationError):
        Settings(_env_file=None)


def test_settings_loads_supabase_fields(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "postgresql+asyncpg://x:y@localhost/z")
    monkeypatch.setenv("SUPABASE_URL", "https://abc.supabase.co")
    monkeypatch.setenv("SUPABASE_ANON_KEY", "anon-public-key")
    monkeypatch.setenv("SUPABASE_SERVICE_ROLE_KEY", "service-role-secret")
    monkeypatch.setenv("SUPABASE_JWT_SECRET", "super-secret")
    monkeypatch.setenv("GOOGLE_OAUTH_CLIENT_ID", "1234.apps.googleusercontent.com")

    s = Settings(_env_file=None)

    assert s.supabase_url == "https://abc.supabase.co"
    assert s.supabase_anon_key == "anon-public-key"
    assert s.supabase_service_role_key == "service-role-secret"
    assert s.supabase_jwt_secret == "super-secret"
    assert s.google_oauth_client_id == "1234.apps.googleusercontent.com"
