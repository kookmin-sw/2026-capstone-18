"""Global FastAPI exception handlers.

Goal: every error response uses `app.schemas.errors.ErrorResponse`.

- `HTTPException` whose `detail` is already an envelope dict (Sprint 3 pattern)
  passes through with its dict promoted to the top level.
- `HTTPException` whose `detail` is a plain string is wrapped in the envelope
  with `reason = "http_<status>"`.
- `RequestValidationError` becomes `reason = "validation_error"` plus the
  field-level error list, and is logged structurally.
- Anything else is logged + 500'd with `reason = "internal_server_error"`.
"""

from __future__ import annotations

from typing import Any

import structlog
from fastapi import FastAPI, HTTPException, Request, Response, status
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

from app.schemas.errors import ErrorResponse

logger = structlog.get_logger(__name__)


def _envelope_from_detail(http_status: int, detail: Any) -> dict[str, Any]:
    if isinstance(detail, dict) and detail.get("status") == "error":
        envelope: dict[str, Any] = {
            "status": "error",
            "reason": detail.get("reason", f"http_{http_status}"),
        }
        if "detail" in detail:
            envelope["detail"] = detail["detail"]
        return envelope
    if isinstance(detail, str):
        return {
            "status": "error",
            "reason": f"http_{http_status}",
            "detail": detail,
        }
    return {
        "status": "error",
        "reason": f"http_{http_status}",
        "detail": str(detail),
    }


async def _http_exception_handler(_request: Request, exc: Exception) -> Response:
    assert isinstance(exc, HTTPException)
    body = _envelope_from_detail(exc.status_code, exc.detail)
    return JSONResponse(status_code=exc.status_code, content=body, headers=exc.headers)


async def _validation_exception_handler(request: Request, exc: Exception) -> Response:
    assert isinstance(exc, RequestValidationError)
    errors = list(exc.errors())
    logger.info(
        "request_validation_failed",
        path=str(request.url.path),
        method=request.method,
        errors=[{"loc": list(e.get("loc", [])), "msg": e.get("msg")} for e in errors],
    )
    body = ErrorResponse.from_validation(errors)
    return JSONResponse(
        status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
        content=body.model_dump(exclude_none=True),
    )


async def _generic_exception_handler(request: Request, exc: Exception) -> Response:
    logger.exception(
        "unhandled_exception",
        path=str(request.url.path),
        method=request.method,
        exc_type=type(exc).__name__,
    )
    body = ErrorResponse(reason="internal_server_error", detail=str(exc))
    return JSONResponse(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        content=body.model_dump(exclude_none=True),
    )


def install_exception_handlers(app: FastAPI) -> None:
    """Idempotent — call once at app startup."""
    app.add_exception_handler(HTTPException, _http_exception_handler)
    app.add_exception_handler(RequestValidationError, _validation_exception_handler)
    app.add_exception_handler(Exception, _generic_exception_handler)
