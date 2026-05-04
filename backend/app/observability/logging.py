"""Structured JSON logging via structlog.

Configure once at app startup with `configure_logging()`. Modules then use:

    import structlog
    log = structlog.get_logger()
    log.info("event_name", user_id="abc", trace_id="def")

Per-request `request_id` is bound via `bind_request_id()` (called by middleware)
and cleared via `clear_request_id()` (called when the request finishes).
"""

from __future__ import annotations

import contextvars
import logging
import sys
from typing import Any

import structlog
from structlog.types import EventDict, Processor

# contextvar holds the current request_id; structlog reads it via a processor
_request_id_var: contextvars.ContextVar[str | None] = contextvars.ContextVar(
    "request_id",
    default=None,
)


def bind_request_id(request_id: str) -> None:
    """Bind the request_id for the current async context."""
    _request_id_var.set(request_id)


def clear_request_id() -> None:
    """Clear the request_id at the end of a request."""
    _request_id_var.set(None)


def _add_request_id(_logger: Any, _method_name: str, event_dict: EventDict) -> EventDict:
    """structlog processor — pulls request_id from contextvar into the log event."""
    request_id = _request_id_var.get()
    if request_id is not None:
        event_dict["request_id"] = request_id
    return event_dict


def configure_logging(level: str = "INFO") -> None:
    """Configure structlog and the stdlib root logger to emit JSON to stdout.

    Idempotent — safe to call multiple times (e.g. in tests).
    """
    numeric_level = getattr(logging, level.upper(), logging.INFO)

    # Replace the root logger's handlers with a single stdout StreamHandler.
    root = logging.getLogger()
    for handler in list(root.handlers):
        root.removeHandler(handler)
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    root.addHandler(handler)
    root.setLevel(numeric_level)

    processors: list[Processor] = [
        structlog.contextvars.merge_contextvars,
        _add_request_id,
        structlog.processors.add_log_level,
        structlog.processors.TimeStamper(fmt="iso", utc=True),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.JSONRenderer(),
    ]

    structlog.configure(
        processors=processors,
        wrapper_class=structlog.make_filtering_bound_logger(numeric_level),
        context_class=dict,
        logger_factory=structlog.PrintLoggerFactory(file=sys.stdout),
        cache_logger_on_first_use=True,
    )
