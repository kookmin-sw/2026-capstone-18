"""Sprint 8a — Sentry init helper tests."""

from __future__ import annotations

from unittest.mock import patch

from app.observability.sentry import _before_send, init_sentry


def test_init_sentry_noop_when_dsn_missing() -> None:
    """No DSN → don't call sentry_sdk.init at all."""
    with patch("app.observability.sentry.sentry_sdk.init") as mock_init:
        init_sentry(dsn=None, environment="local", release="0.8.0")
    mock_init.assert_not_called()


def test_init_sentry_passes_config_when_dsn_set() -> None:
    """DSN set → init with environment, release, send_default_pii=False."""
    with patch("app.observability.sentry.sentry_sdk.init") as mock_init:
        init_sentry(
            dsn="https://abc@o123.ingest.sentry.io/456",
            environment="staging",
            release="0.8.0",
        )
    mock_init.assert_called_once()
    kwargs = mock_init.call_args.kwargs
    assert kwargs["dsn"] == "https://abc@o123.ingest.sentry.io/456"
    assert kwargs["environment"] == "staging"
    assert kwargs["release"] == "0.8.0"
    assert kwargs["send_default_pii"] is False
    assert kwargs["before_send"] is _before_send


def test_before_send_scrubs_authorization_header() -> None:
    """Authorization headers must never reach Sentry."""
    event = {
        "request": {
            "headers": {"authorization": "Bearer secret-token", "user-agent": "test"},
        },
    }
    out = _before_send(event, hint={})
    assert out is not None
    assert out["request"]["headers"]["authorization"] == "[scrubbed]"
    assert out["request"]["headers"]["user-agent"] == "test"


def test_before_send_scrubs_cookie_header() -> None:
    event = {"request": {"headers": {"cookie": "session=abc"}}}
    out = _before_send(event, hint={})
    assert out is not None
    assert out["request"]["headers"]["cookie"] == "[scrubbed]"


def test_before_send_passes_through_clean_event() -> None:
    event = {"request": {"headers": {"x-request-id": "abc"}}}
    out = _before_send(event, hint={})
    assert out == event


def test_before_send_scrubs_apikey_header() -> None:
    """Supabase outbound calls send `apikey: <service-role-key>` — must scrub."""
    event = {"request": {"headers": {"apikey": "secret-service-role-key"}}}
    out = _before_send(event, hint={})
    assert out is not None
    assert out["request"]["headers"]["apikey"] == "[scrubbed]"


def test_before_send_scrubs_x_supabase_token_header() -> None:
    event = {"request": {"headers": {"x-supabase-token": "raw-jwt"}}}
    out = _before_send(event, hint={})
    assert out is not None
    assert out["request"]["headers"]["x-supabase-token"] == "[scrubbed]"
