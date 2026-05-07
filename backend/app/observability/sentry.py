"""Sentry SDK initialization.

Idempotent helper called once at app startup from `app.main`. We skip init
when the DSN is missing, blank, or a placeholder so local dev, CI, and
freshly-applied staging environments (where the Secrets Manager value is
populated post-apply) don't crash on startup. AWS Secrets Manager rejects
empty strings, so any deploy that creates the secret resource ahead of
populating it has to seed *some* value — we tolerate the obvious
placeholders rather than letting the SDK raise `BadDsn`.

PII scrubbing: `send_default_pii=False` blocks the SDK from auto-attaching
client IPs, cookie headers, and form data. `_before_send` adds explicit
scrubbing of `authorization` and `cookie` headers as belt-and-braces.
"""

from __future__ import annotations

from typing import TYPE_CHECKING, Any, cast

import sentry_sdk
from sentry_sdk.integrations.fastapi import FastApiIntegration
from sentry_sdk.integrations.starlette import StarletteIntegration

if TYPE_CHECKING:
    from sentry_sdk._types import EventProcessor

_SCRUB_HEADERS = {"authorization", "cookie", "x-supabase-token", "apikey"}

# DSNs we treat as "not set" even though Secrets Manager has a non-empty value.
# Anything else that doesn't parse cleanly will still be caught by `_dsn_is_real`.
_PLACEHOLDER_DSN_HOSTS = ("noop.invalid", "example.com", "example.invalid")


def _dsn_is_real(dsn: str | None) -> bool:
    if not dsn or not dsn.strip():
        return False
    candidate = dsn.strip().lower()
    if not (candidate.startswith("http://") or candidate.startswith("https://")):
        return False
    return not any(host in candidate for host in _PLACEHOLDER_DSN_HOSTS)


def _before_send(event: dict[str, Any], hint: dict[str, Any]) -> dict[str, Any] | None:
    headers = event.get("request", {}).get("headers")
    if isinstance(headers, dict):
        for key in list(headers.keys()):
            if key.lower() in _SCRUB_HEADERS:
                headers[key] = "[scrubbed]"
    return event


def init_sentry(*, dsn: str | None, environment: str, release: str) -> None:
    if not _dsn_is_real(dsn):
        return
    sentry_sdk.init(
        dsn=dsn,
        environment=environment,
        release=release,
        send_default_pii=False,
        traces_sample_rate=0.0,  # OpenTelemetry owns tracing; Sentry handles errors only
        integrations=[FastApiIntegration(), StarletteIntegration()],
        before_send=cast("EventProcessor", _before_send),
    )
