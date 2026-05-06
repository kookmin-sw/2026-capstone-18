"""Standard error envelope.

Every non-success response from this API uses this shape:

    {
      "status": "error",
      "reason": "<machine_code>",
      "detail": "<optional human-readable string>",
      "errors": [{"loc": [...], "msg": "..."}]   // only for 422
    }
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel


class ErrorItem(BaseModel):
    loc: list[str | int]
    msg: str
    type: str | None = None


class ErrorResponse(BaseModel):
    status: str = "error"
    reason: str
    detail: str | None = None
    errors: list[ErrorItem] | None = None

    @classmethod
    def from_validation(cls, errors: list[dict[str, Any]]) -> ErrorResponse:
        return cls(
            reason="validation_error",
            detail="Request body failed validation.",
            errors=[
                ErrorItem(loc=list(e.get("loc", [])), msg=e.get("msg", ""), type=e.get("type"))
                for e in errors
            ],
        )
