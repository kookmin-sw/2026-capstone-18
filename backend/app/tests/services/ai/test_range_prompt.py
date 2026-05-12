"""Tests for range_report_prompt: shape and dynamic duration."""

from __future__ import annotations

from datetime import date

from app.services.ai.prompts import range_report_prompt


def test_range_prompt_includes_dynamic_duration_and_dates() -> None:
    system, user = range_report_prompt(
        display_name="이현이",
        period_start=date(2026, 4, 1),
        period_end=date(2026, 5, 31),
        n_events=12,
        events_summary_lines=["Mon 09:00 · 강도 3"],
        n_sleep=5,
        avg_sleep_min=420,
        avg_rating="좋음",
        sleep_lines=["2026-04-15 420분 (좋음)"],
        current_phase="luteal",
        phase_changes="(미집계)",
        top_pattern_lines=["업무 · 황체기 (+30%, 4건)"],
    )
    assert "61일간" in system
    assert "JSON" in system
    assert "2026-04-01" in user
    assert "2026-05-31" in user
    assert "61일" in user
    assert "이현이" in user
    assert "업무 · 황체기 (+30%, 4건)" in user


def test_range_prompt_single_day() -> None:
    system, user = range_report_prompt(
        display_name="A",
        period_start=date(2026, 5, 12),
        period_end=date(2026, 5, 12),
        n_events=0,
        events_summary_lines=[],
        n_sleep=0,
        avg_sleep_min=0,
        avg_rating="—",
        sleep_lines=[],
        current_phase="unknown",
        phase_changes="(미집계)",
        top_pattern_lines=[],
    )
    assert "1일간" in system
    assert "1일" in user
