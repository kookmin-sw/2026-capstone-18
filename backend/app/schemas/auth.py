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


class EmailSignUpRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=254)
    password: str = Field(..., min_length=8, max_length=128)
    display_name: str | None = Field(default=None, max_length=64)


class EmailSignInRequest(BaseModel):
    email: str = Field(..., min_length=3, max_length=254)
    password: str = Field(..., min_length=1, max_length=128)


class PasswordForgotRequest(BaseModel):
    """POST /auth/password/forgot body. Always returns 200 to avoid enumeration."""

    email: str = Field(..., min_length=3, max_length=254)


class PasswordResetRequest(BaseModel):
    """POST /auth/password/reset body. otp is the 6-digit code from email."""

    email: str = Field(..., min_length=3, max_length=254)
    otp: str = Field(..., min_length=6, max_length=10, pattern=r"^[0-9]+$")
    new_password: str = Field(..., min_length=8, max_length=128)
