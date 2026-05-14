"""Async HTTP wrapper around the four Supabase Auth REST calls we need.

Endpoints used (all relative to ``<supabase_url>/auth/v1``):

- ``POST /signup`` with ``{}`` body — creates an anonymous user when anonymous
  sign-ins are enabled.
- ``POST /token?grant_type=id_token`` — id-token grant (Google).
- ``POST /token?grant_type=refresh_token`` — refresh.
- ``POST /logout`` — sign out a session token.
- ``PATCH /admin/users/{id}`` — admin update (email, user_metadata) for the
  anon→Google upgrade.

The client holds two credentials: the anon key (used as the ``Authorization``
header for non-admin calls; required by Supabase's gateway) and the service
role key (used for admin calls). The caller's session token, when present,
goes in a separate ``Authorization`` override per Supabase conventions.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass
from typing import Any

import httpx


class SupabaseAuthError(Exception):
    """Supabase returned a non-success status."""

    def __init__(self, status_code: int, body: Any) -> None:
        super().__init__(f"Supabase auth error {status_code}: {body}")
        self.status_code = status_code
        self.body = body


@dataclass(frozen=True)
class SupabaseSession:
    access_token: str
    refresh_token: str
    expires_in: int
    user_id: uuid.UUID
    is_anonymous: bool
    email: str | None = None


class SupabaseAuthClient:
    def __init__(
        self,
        *,
        url: str,
        anon_key: str,
        service_role_key: str,
        timeout: float = 10.0,
    ) -> None:
        self._base = f"{url.rstrip('/')}/auth/v1"
        self._anon_key = anon_key
        self._service_role_key = service_role_key
        self._timeout = timeout

    def _client(self, *, admin: bool = False) -> httpx.AsyncClient:
        key = self._service_role_key if admin else self._anon_key
        return httpx.AsyncClient(
            base_url=self._base,
            timeout=self._timeout,
            headers={"apikey": key, "Authorization": f"Bearer {key}"},
        )

    @staticmethod
    def _session_from_response(payload: dict[str, Any]) -> SupabaseSession:
        user = payload.get("user") or {}
        return SupabaseSession(
            access_token=payload["access_token"],
            refresh_token=payload["refresh_token"],
            expires_in=int(payload.get("expires_in", 0)),
            user_id=uuid.UUID(user["id"]),
            is_anonymous=bool(user.get("is_anonymous", False)),
            email=user.get("email"),
        )

    async def sign_in_anonymously(self) -> SupabaseSession:
        async with self._client() as http:
            r = await http.post("/signup", json={})
        if r.status_code != 200:
            raise SupabaseAuthError(r.status_code, r.text)
        return self._session_from_response(r.json())

    async def sign_in_with_id_token(self, *, provider: str, id_token: str) -> SupabaseSession:
        async with self._client() as http:
            r = await http.post(
                "/token",
                params={"grant_type": "id_token"},
                json={"provider": provider, "id_token": id_token},
            )
        if r.status_code != 200:
            raise SupabaseAuthError(r.status_code, r.text)
        return self._session_from_response(r.json())

    async def sign_in_with_password(self, *, email: str, password: str) -> SupabaseSession:
        async with self._client() as http:
            r = await http.post(
                "/token",
                params={"grant_type": "password"},
                json={"email": email, "password": password},
            )
        if r.status_code != 200:
            raise SupabaseAuthError(r.status_code, r.text)
        return self._session_from_response(r.json())

    async def sign_up_with_email(
        self,
        *,
        email: str,
        password: str,
        user_metadata: dict[str, Any] | None = None,
        email_confirm: bool = True,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {
            "email": email,
            "password": password,
            "email_confirm": email_confirm,
        }
        if user_metadata is not None:
            body["user_metadata"] = user_metadata
        async with self._client(admin=True) as http:
            r = await http.post("/admin/users", json=body)
        if r.status_code not in (200, 201):
            raise SupabaseAuthError(r.status_code, r.text)
        result: dict[str, Any] = r.json()
        return result

    async def refresh_session(self, refresh_token: str) -> SupabaseSession:
        async with self._client() as http:
            r = await http.post(
                "/token",
                params={"grant_type": "refresh_token"},
                json={"refresh_token": refresh_token},
            )
        if r.status_code != 200:
            raise SupabaseAuthError(r.status_code, r.text)
        return self._session_from_response(r.json())

    async def sign_out(self, access_token: str) -> None:
        async with self._client() as http:
            r = await http.post(
                "/logout",
                headers={"Authorization": f"Bearer {access_token}"},
            )
        if r.status_code not in (204, 200):
            raise SupabaseAuthError(r.status_code, r.text)

    async def request_password_recovery(self, *, email: str) -> int:
        """POST /recover. Returns the Supabase status code; caller decides
        how to log it (4xx and 5xx are intentionally NOT raised — the public
        endpoint always returns 200 to the user to defend against account
        enumeration).
        """
        async with self._client() as http:
            r = await http.post("/recover", json={"email": email})
        return r.status_code

    async def verify_recovery_otp_and_set_password(
        self, *, email: str, otp: str, new_password: str
    ) -> SupabaseSession:
        """Verify the recovery OTP, then update password.

        Two-step:
          1. POST /verify {type:"recovery", email, token: otp} → access_token
          2. PUT /user {password: new_password} authenticated with that token

        Returns a SupabaseSession reflecting the post-password-change state.
        Raises SupabaseAuthError on either step's non-success.
        """
        async with self._client() as http:
            verify_r = await http.post(
                "/verify",
                json={"type": "recovery", "email": email, "token": otp},
            )
        if verify_r.status_code != 200:
            raise SupabaseAuthError(verify_r.status_code, verify_r.text)

        verify_payload = verify_r.json()
        access_token: str = verify_payload["access_token"]

        async with self._client() as http:
            update_r = await http.put(
                "/user",
                json={"password": new_password},
                headers={"Authorization": f"Bearer {access_token}"},
            )
        if update_r.status_code != 200:
            raise SupabaseAuthError(update_r.status_code, update_r.text)

        return self._session_from_response(verify_payload)

    async def admin_update_user(
        self,
        user_id: uuid.UUID,
        *,
        email: str | None = None,
        user_metadata: dict[str, Any] | None = None,
        email_confirm: bool = True,
    ) -> dict[str, Any]:
        body: dict[str, Any] = {}
        if email is not None:
            body["email"] = email
            body["email_confirm"] = email_confirm
        if user_metadata is not None:
            body["user_metadata"] = user_metadata
        async with self._client(admin=True) as http:
            r = await http.patch(f"/admin/users/{user_id}", json=body)
        if r.status_code != 200:
            raise SupabaseAuthError(r.status_code, r.text)
        result: dict[str, Any] = r.json()
        return result
