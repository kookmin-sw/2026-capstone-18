"""FastAPI application entrypoint.

Run locally with:
    poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import uuid
from collections.abc import Awaitable, Callable
from typing import Annotated

from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.dependencies import get_db
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

from app.observability.exception_handlers import install_exception_handlers  # noqa: E402

install_exception_handlers(app)


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


@app.get("/ready")
async def ready(db: Annotated[AsyncSession, Depends(get_db)]) -> dict[str, str]:
    """Readiness probe. Returns 200 only when core dependencies respond."""
    try:
        await db.execute(text("SELECT 1"))
    except Exception as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail={"status": "error", "reason": "database_unreachable"},
        ) from exc
    return {"status": "ok", "database": "ok"}


from app.account.router import router as account_router  # noqa: E402
from app.auth.router import router as auth_router  # noqa: E402
from app.consent.router import router as consent_router  # noqa: E402
from app.cycles.router import router as cycles_router  # noqa: E402
from app.events.router import router as events_router  # noqa: E402
from app.realtime.router import router as realtime_router  # noqa: E402
from app.settings_api.router import router as settings_router  # noqa: E402

app.include_router(auth_router, prefix="/api/v1")
app.include_router(account_router, prefix="/api/v1")
app.include_router(events_router, prefix="/api/v1")
app.include_router(cycles_router, prefix="/api/v1")
app.include_router(settings_router, prefix="/api/v1")
app.include_router(consent_router, prefix="/api/v1")
app.include_router(realtime_router)
