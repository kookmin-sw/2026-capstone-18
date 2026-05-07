"""Sprint 8a — OTel tracing init tests."""

from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest
from fastapi import FastAPI

from app.observability.tracing import init_tracing


@pytest.fixture(autouse=True)
def _reset_tracer_provider() -> None:
    """Tests share global state in opentelemetry.trace; reset between tests."""
    from opentelemetry import trace
    from opentelemetry.util._once import Once

    trace._TRACER_PROVIDER_SET_ONCE = Once()
    trace._TRACER_PROVIDER = None


def test_init_tracing_noop_when_endpoint_missing() -> None:
    """No OTLP endpoint → don't install a span exporter."""
    app = FastAPI()
    with (
        patch("app.observability.tracing.OTLPSpanExporter") as mock_exporter,
        patch("app.observability.tracing.FastAPIInstrumentor") as mock_fastapi,
        patch("app.observability.tracing.SQLAlchemyInstrumentor"),
    ):
        init_tracing(app, service_name="test", otlp_endpoint=None, environment="local")
    mock_exporter.assert_not_called()
    # FastAPI instrumentation is still installed (so spans exist locally even without export)
    mock_fastapi.instrument_app.assert_called_once_with(app)


def test_init_tracing_installs_otlp_exporter_when_endpoint_set() -> None:
    app = FastAPI()
    with (
        patch("app.observability.tracing.OTLPSpanExporter") as mock_exporter,
        patch("app.observability.tracing.BatchSpanProcessor") as mock_processor,
        patch("app.observability.tracing.FastAPIInstrumentor"),
        patch("app.observability.tracing.SQLAlchemyInstrumentor") as mock_sqla,
    ):
        mock_sqla.return_value = MagicMock()
        init_tracing(
            app,
            service_name="little-signals-backend",
            otlp_endpoint="http://localhost:4317",
            environment="staging",
        )
    mock_exporter.assert_called_once_with(endpoint="http://localhost:4317", insecure=True)
    mock_processor.assert_called_once()


def test_init_tracing_uses_aws_xray_id_generator_for_aws_envs() -> None:
    """staging + production → use the AWS X-Ray ID generator so spans align with X-Ray traceIds."""
    app = FastAPI()
    with (
        patch("app.observability.tracing.AwsXRayIdGenerator") as mock_xray_idgen,
        patch("app.observability.tracing.TracerProvider") as mock_provider,
        patch("app.observability.tracing.FastAPIInstrumentor"),
        patch("app.observability.tracing.SQLAlchemyInstrumentor"),
    ):
        init_tracing(
            app,
            service_name="svc",
            otlp_endpoint="http://localhost:4317",
            environment="staging",
        )
    mock_xray_idgen.assert_called_once()
    # Provider was constructed with the X-Ray id_generator
    _, kwargs = mock_provider.call_args
    assert "id_generator" in kwargs


def test_notification_dispatch_creates_manual_span(monkeypatch: pytest.MonkeyPatch) -> None:
    """notify_user wraps its work in a span called 'notify_user'."""
    import asyncio
    import uuid as _uuid
    from typing import Any
    from unittest.mock import MagicMock

    from opentelemetry import trace
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from opentelemetry.sdk.trace.export.in_memory_span_exporter import InMemorySpanExporter

    exporter = InMemorySpanExporter()
    provider = TracerProvider()
    provider.add_span_processor(SimpleSpanProcessor(exporter))
    monkeypatch.setattr(
        "app.services.notifications.tracer",
        trace.get_tracer("test", tracer_provider=provider),
    )

    async def _ws(user_id: Any, msg: Any) -> int:
        return 1

    monkeypatch.setattr("app.services.notifications.manager.broadcast_to_user", _ws)

    from app.schemas.realtime import OutboundMessage
    from app.services.notifications import notifier

    msg = OutboundMessage(type="events.created", data={})
    asyncio.run(notifier.notify_user(MagicMock(), user_id=_uuid.uuid4(), message=msg))

    span_names = [s.name for s in exporter.get_finished_spans()]
    assert "notify_user" in span_names
