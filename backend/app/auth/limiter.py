"""Shared rate-limiter instance for auth endpoints."""

from __future__ import annotations

from slowapi import Limiter
from slowapi.util import get_remote_address

# NOTE: relies on ProxyHeadersMiddleware in main.py to populate
# request.client.host from X-Forwarded-For when behind ALB.
# For multi-instance deployments, switch storage to Redis.
limiter = Limiter(key_func=get_remote_address)
