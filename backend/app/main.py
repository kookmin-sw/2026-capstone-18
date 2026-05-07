"""FastAPI application entrypoint.

Run locally with:
    poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

import asyncio
import contextlib
import uuid
from collections.abc import AsyncIterator, Awaitable, Callable
from contextlib import asynccontextmanager
from typing import Annotated

import structlog
from fastapi import Depends, FastAPI, HTTPException, Request, Response, status
from fastapi.responses import RedirectResponse
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import get_settings
from app.db.dependencies import get_db
from app.db.session import AsyncSessionLocal
from app.observability.logging import bind_request_id, clear_request_id, configure_logging
from app.realtime.cleanup import clear_task_connections, sweep_stale_connections
from app.services.fcm import init_firebase

settings = get_settings()

configure_logging(level=settings.log_level)

from app.observability.sentry import init_sentry  # noqa: E402

init_sentry(
    dsn=settings.sentry_dsn,
    environment=settings.environment,
    release=settings.app_version,
)

logger = structlog.get_logger(__name__)


async def _sweep_loop() -> None:
    """Background task: sweep stale websocket_connections rows every 60s.

    Stays in-process — 60s is below EventBridge's 1-minute floor. Exceptions
    are swallowed so the loop never crashes — log spam is fine, a wedged
    loop is not.
    """
    cfg = get_settings()
    while True:
        try:
            async with AsyncSessionLocal() as db:
                await sweep_stale_connections(
                    db, idle_timeout_seconds=cfg.websocket_idle_timeout_seconds
                )
                await db.commit()
        except Exception:  # noqa: BLE001
            logger.exception("websocket_sweep_failed")
        await asyncio.sleep(60)


@asynccontextmanager
async def _lifespan(app: FastAPI) -> AsyncIterator[None]:
    """App lifespan: clear this task's stale rows on startup, then sweep periodically."""
    init_firebase()
    cfg = get_settings()
    async with AsyncSessionLocal() as db:
        await clear_task_connections(db, task_id=cfg.task_id)
        await db.commit()

    sweep_task = asyncio.create_task(_sweep_loop())
    try:
        yield
    finally:
        sweep_task.cancel()
        with contextlib.suppress(asyncio.CancelledError):
            await sweep_task


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
    lifespan=_lifespan,
)

from app.observability.metrics import setup_metrics  # noqa: E402

setup_metrics(app)

from app.observability.tracing import init_tracing  # noqa: E402

init_tracing(
    app,
    service_name="little-signals-backend",
    otlp_endpoint=settings.otel_exporter_otlp_endpoint,
    environment=settings.environment,
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
from app.devices.router import router as devices_router  # noqa: E402
from app.events.router import router as events_router  # noqa: E402
from app.realtime.router import router as realtime_router  # noqa: E402
from app.settings_api.router import router as settings_router  # noqa: E402
from app.sync.router import router as sync_router  # noqa: E402

app.include_router(auth_router, prefix="/api/v1")
app.include_router(account_router, prefix="/api/v1")
app.include_router(events_router, prefix="/api/v1")
app.include_router(cycles_router, prefix="/api/v1")
app.include_router(settings_router, prefix="/api/v1")
app.include_router(consent_router, prefix="/api/v1")
app.include_router(devices_router, prefix="/api/v1")
app.include_router(sync_router, prefix="/api/v1")
app.include_router(realtime_router)
