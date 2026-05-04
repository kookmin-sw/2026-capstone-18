"""FastAPI application entrypoint.

Run locally with:
    poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable

from fastapi import FastAPI, Request, Response
from fastapi.responses import RedirectResponse

from app.config import get_settings
from app.observability.logging import bind_request_id, clear_request_id, configure_logging

settings = get_settings()

configure_logging(level=settings.log_level)

app = FastAPI(
    title="little-signals backend",
    description=(
        "Backend service for Project Phase — women-focused stress detection "
        "and cycle tracking on Galaxy Watch 8 + Android."
    ),
    version=settings.app_version,
    docs_url="/docs",
    redoc_url="/redoc",
    openapi_url="/openapi.json",
)


@app.middleware("http")
async def request_id_middleware(
    request: Request,
    call_next: Callable[[Request], Awaitable[Response]],
) -> Response:
    """Bind a per-request UUID to structlog context and echo it back as a header.

    Honors a client-supplied X-Request-ID if present (so a frontend or upstream
    proxy can correlate its logs with ours). Otherwise generates a fresh UUID v4.
    """
    request_id = request.headers.get("x-request-id") or str(uuid.uuid4())
    bind_request_id(request_id)
    try:
        response = await call_next(request)
    finally:
        clear_request_id()
    response.headers["x-request-id"] = request_id
    return response


@app.get("/", include_in_schema=False)
async def root() -> RedirectResponse:
    """Redirect root to the Swagger UI for dev convenience."""
    return RedirectResponse(url="/docs")


@app.get("/health")
async def health() -> dict[str, str]:
    """Liveness probe. Returns 200 when the process is up.

    Sprint 1 reports `status` and `version`. Sprint 2 will add `git_sha`
    and basic dependency status (DB reachable yes/no).
    """
    return {"status": "ok", "version": settings.app_version}
