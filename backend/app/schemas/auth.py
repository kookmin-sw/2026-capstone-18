"""Pydantic models for auth router request/response shapes."""

from __future__ import annotations

from pydantic import BaseModel, Field


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    expires_in: int
    token_type: str = "bearer"
    is_anonymous: bool


class GoogleSignInRequest(BaseModel):
    id_token: str = Field(..., min_length=1, description="Google-issued OIDC ID token.")


class RefreshRequest(BaseModel):
    refresh_token: str = Field(..., min_length=1)


class LogoutResponse(BaseModel):
    status: str = "ok"
