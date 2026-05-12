"""End-to-end tests for GET /api/v1/reports/range."""

from __future__ import annotations

import uuid
from datetime import UTC, date, datetime
from typing import Any
from unittest.mock import MagicMock, patch

import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.range_report import RangeReport


def _ai_enabled_settings() -> MagicMock:
    """Return a Settings-like mock with AI features enabled."""
    s = MagicMock()
    s.ai_features_enabled = True
    return s


@pytest.mark.asyncio
async def test_rejects_when_frm_after_to(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """frm > to must yield 422."""
    me = await make_user()
    with patch("app.reports.router.get_settings", return_value=_ai_enabled_settings()):
        resp = await client.get(
            "/api/v1/reports/range?frm=2026-05-30&to=2026-05-01",
            headers=auth_headers(str(me.supabase_user_id)),
        )
    assert resp.status_code == 422
    body = resp.json()
    reason = body.get("reason") or (body.get("detail") or {}).get("reason")
    assert reason == "frm_must_be_le_to"


@pytest.mark.asyncio
async def test_returns_404_when_ai_disabled(
    client: AsyncClient,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """When ai_features_enabled is False the endpoint returns 404."""
    me = await make_user()
    # Default settings already have ai_features_enabled=False; no patch needed.
    resp = await client.get(
        "/api/v1/reports/range?frm=2026-05-01&to=2026-05-31",
        headers=auth_headers(str(me.supabase_user_id)),
    )
    assert resp.status_code == 404
    body = resp.json()
    reason = body.get("reason") or (body.get("detail") or {}).get("reason")
    assert reason == "ai_disabled"


@pytest.mark.asyncio
async def test_generates_on_first_call_and_persists(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """First GET with no cached row calls the generator and returns 200."""
    me = await make_user()

    frm = date(2026, 5, 1)
    to = date(2026, 5, 31)
    expected_headline = "5월 종합 리포트"

    async def _fake_generate(
        db: AsyncSession,
        *,
        user_id: uuid.UUID,
        period_start: date,
        period_end: date,
    ) -> RangeReport:
        row = RangeReport(
            user_id=user_id,
            period_start=period_start,
            period_end=period_end,
            headline=expected_headline,
            body_md="## 요약\n내용",
            takeaways=[{"title": "포인트", "body": "설명"}],
            generated_at=datetime.now(UTC),
        )
        db.add(row)
        await db.flush()
        return row

    mock_instance = MagicMock()
    mock_instance.generate = _fake_generate
    mock_cls = MagicMock(return_value=mock_instance)

    with (
        patch("app.reports.router.get_settings", return_value=_ai_enabled_settings()),
        patch("app.reports.router.RangeReportGenerator", mock_cls),
    ):
        resp = await client.get(
            f"/api/v1/reports/range?frm={frm}&to={to}",
            headers=auth_headers(str(me.supabase_user_id)),
        )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["headline"] == expected_headline
    assert body["period_start"] == str(frm)
    assert body["period_end"] == str(to)
    assert mock_cls.call_count == 1


@pytest.mark.asyncio
async def test_cache_hit_skips_generation_when_no_new_data(
    client: AsyncClient,
    db_session: AsyncSession,
    supabase_jwt_secret: str,  # noqa: ARG001
    auth_headers: Any,
    make_user: Any,
) -> None:
    """Pre-seeded RangeReport with no events → generator is NOT called."""
    me = await make_user()

    frm = date(2026, 4, 1)
    to = date(2026, 4, 30)
    seeded_headline = "4월 캐시 리포트"

    row = RangeReport(
        user_id=me.id,
        period_start=frm,
        period_end=to,
        headline=seeded_headline,
        body_md="## 캐시\n내용",
        takeaways=[],
        generated_at=datetime.now(UTC),
    )
    db_session.add(row)
    await db_session.flush()

    mock_cls = MagicMock()

    with (
        patch("app.reports.router.get_settings", return_value=_ai_enabled_settings()),
        patch("app.reports.router.RangeReportGenerator", mock_cls),
    ):
        resp = await client.get(
            f"/api/v1/reports/range?frm={frm}&to={to}",
            headers=auth_headers(str(me.supabase_user_id)),
        )

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["headline"] == seeded_headline
    # Generator was never instantiated — cache hit.
    assert mock_cls.call_count == 0
