"""Prometheus metrics — custom counters/gauges/histograms + /metrics endpoint.

Custom metrics live at module level so callers (events router, notification
service, websocket manager) import them directly:

    from app.observability.metrics import events_created_total
    events_created_total.inc()

The Instrumentator covers per-request HTTP metrics (duration, status, path)
automatically. We add four custom metrics on top, matching spec §13.6.
"""

from __future__ import annotations

from fastapi import FastAPI
from prometheus_client import Counter, Gauge, Histogram
from prometheus_fastapi_instrumentator import Instrumentator

events_created_total = Counter(
    "events_created_total",
    "Stress events created via POST /api/v1/events.",
)

notifications_sent_total = Counter(
    "notifications_sent_total",
    "Outbound user notifications dispatched, labeled by transport.",
    ["type"],
)

active_websocket_connections = Gauge(
    "active_websocket_connections",
    "Live WebSocket connections held by THIS task (process-local).",
)

db_query_duration_seconds = Histogram(
    "db_query_duration_seconds",
    "Async SQLAlchemy query duration (seconds).",
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0),
)


def setup_metrics(app: FastAPI) -> None:
    """Wire prometheus-fastapi-instrumentator and expose /metrics."""
    Instrumentator(
        excluded_handlers=["/metrics", "/health", "/ready"],
    ).instrument(app).expose(app, endpoint="/metrics", include_in_schema=False)
