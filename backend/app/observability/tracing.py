"""OpenTelemetry tracing setup.

Called once at startup from `app.main`. When `otlp_endpoint` is None we still
install the FastAPI + SQLAlchemy instrumentors (so spans exist for any in-process
tooling), but skip the OTLP exporter — local dev runs without an ADOT sidecar.

In AWS environments we use the X-Ray ID generator (128-bit, time-prefixed) so
spans correlate with X-Ray's expected trace ID format. Local dev uses the OTel
default random ID generator.

`tracer` is exported so other modules can create manual spans:

    from app.observability.tracing import tracer
    with tracer.start_as_current_span("notify_user"):
        ...
"""

from __future__ import annotations

from typing import Any

from fastapi import FastAPI
from opentelemetry import trace
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.instrumentation.sqlalchemy import SQLAlchemyInstrumentor
from opentelemetry.sdk.extension.aws.trace import AwsXRayIdGenerator
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def init_tracing(
    app: FastAPI,
    *,
    service_name: str,
    otlp_endpoint: str | None,
    environment: str,
) -> None:
    resource = Resource.create(
        {
            "service.name": service_name,
            "service.namespace": "little-signals",
            "deployment.environment": environment,
        }
    )

    provider_kwargs: dict[str, Any] = {"resource": resource}
    if environment in ("staging", "production"):
        provider_kwargs["id_generator"] = AwsXRayIdGenerator()

    provider = TracerProvider(**provider_kwargs)

    if otlp_endpoint:
        exporter = OTLPSpanExporter(endpoint=otlp_endpoint, insecure=True)
        provider.add_span_processor(BatchSpanProcessor(exporter))

    trace.set_tracer_provider(provider)

    FastAPIInstrumentor.instrument_app(app)
    # SQLAlchemy instrumentation is installed at the engine level. We import the
    # engine lazily so test imports of this module don't pull the DB stack.
    from app.db.session import engine

    SQLAlchemyInstrumentor().instrument(engine=engine.sync_engine)


tracer = trace.get_tracer("little-signals-backend")
