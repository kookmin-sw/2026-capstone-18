"""Sentry SDK initialization.

Idempotent helper called once at app startup from `app.main`. When `dsn` is
None we skip init entirely so local dev and CI don't pollute the team's
Sentry project (or fail because the DSN env var is unset).

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


def _before_send(event: dict[str, Any], hint: dict[str, Any]) -> dict[str, Any] | None:
    headers = event.get("request", {}).get("headers")
    if isinstance(headers, dict):
        for key in list(headers.keys()):
            if key.lower() in _SCRUB_HEADERS:
                headers[key] = "[scrubbed]"
    return event


def init_sentry(*, dsn: str | None, environment: str, release: str) -> None:
    if not dsn:
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
