"""Sprint 8a — custom Prometheus counter increments tied to real endpoints."""

from __future__ import annotations

from datetime import UTC, datetime
from typing import Any

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.observability.metrics import events_created_total


@pytest.mark.asyncio
async def test_events_created_total_increments_on_post_event(
    client: AsyncClient,
    db_session: AsyncSession,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    me = await make_user()
    before = events_created_total._value.get()
    payload: dict[str, Any] = {
        "detected_at": datetime.now(UTC).isoformat(),
        "model_confidence": 0.8,
    }
    resp = await client.post(
        "/api/v1/events",
        json=payload,
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 201, resp.text
    after = events_created_total._value.get()
    assert after == before + 1


@pytest.mark.asyncio
async def test_notifications_sent_total_websocket_increments(
    db_session: AsyncSession,
    make_user: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.observability.metrics import notifications_sent_total
    from app.schemas.realtime import OutboundMessage
    from app.services.notifications import notifier

    me = await make_user()

    async def _fake_ws(user_id: Any, msg: Any) -> int:
        return 1

    monkeypatch.setattr(
        "app.services.notifications.manager.broadcast_to_user",
        _fake_ws,
    )

    before = notifications_sent_total.labels(type="websocket")._value.get()
    msg = OutboundMessage(type="events.created", data={})
    await notifier.notify_user(db_session, user_id=me.id, message=msg)
    after = notifications_sent_total.labels(type="websocket")._value.get()
    assert after == before + 1


@pytest.mark.asyncio
async def test_notifications_sent_total_fcm_increments(
    db_session: AsyncSession,
    make_user: Any,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    from app.observability.metrics import notifications_sent_total
    from app.schemas.realtime import OutboundMessage
    from app.services.notifications import notifier

    me = await make_user()

    async def _no_ws(user_id: Any, msg: Any) -> int:
        return 0

    async def _two_fcm(db: Any, *, user_id: Any, payload: dict[str, Any]) -> int:
        return 2

    monkeypatch.setattr("app.services.notifications.manager.broadcast_to_user", _no_ws)
    monkeypatch.setattr("app.services.notifications.send_to_user", _two_fcm)

    before = notifications_sent_total.labels(type="fcm")._value.get()
    msg = OutboundMessage(type="events.created", data={})
    await notifier.notify_user(db_session, user_id=me.id, message=msg)
    after = notifications_sent_total.labels(type="fcm")._value.get()
    assert after == before + 2


def test_active_websocket_connections_gauge_tracks_attach_detach() -> None:
    import uuid as _uuid
    from unittest.mock import MagicMock

    from app.observability.metrics import active_websocket_connections
    from app.realtime.manager import ConnectionManager

    mgr = ConnectionManager()
    before = active_websocket_connections._value.get()

    cid = _uuid.uuid4()
    uid = _uuid.uuid4()
    mgr.attach(connection_id=cid, user_id=uid, websocket=MagicMock())
    assert active_websocket_connections._value.get() == before + 1

    mgr.detach(connection_id=cid)
    assert active_websocket_connections._value.get() == before
