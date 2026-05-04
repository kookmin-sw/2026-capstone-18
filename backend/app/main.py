"""FastAPI application entrypoint.

Run locally with:
    poetry run uvicorn app.main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from fastapi import FastAPI
from fastapi.responses import RedirectResponse

from app.config import get_settings

settings = get_settings()

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
