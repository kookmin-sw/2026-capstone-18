"""Tests for structlog configuration."""

from __future__ import annotations

import json
import logging

import structlog

from app.observability.logging import bind_request_id, clear_request_id, configure_logging


def test_configure_logging_outputs_json(capsys) -> None:  # type: ignore[no-untyped-def]
    configure_logging(level="INFO")
    log = structlog.get_logger()

    log.info("hello", user_id="abc")

    captured = capsys.readouterr()
    line = captured.out.strip().splitlines()[-1]
    payload = json.loads(line)
    assert payload["event"] == "hello"
    assert payload["user_id"] == "abc"
    assert payload["level"] == "info"
    assert "timestamp" in payload


def test_configure_logging_respects_level(capsys) -> None:  # type: ignore[no-untyped-def]
    configure_logging(level="WARNING")
    log = structlog.get_logger()

    log.info("ignored")
    log.warning("kept", code=42)

    captured = capsys.readouterr()
    lines = [line for line in captured.out.strip().splitlines() if line]
    payloads = [json.loads(line) for line in lines]
    events = [p["event"] for p in payloads]
    assert "ignored" not in events
    assert "kept" in events


def test_request_id_binding_round_trip(capsys) -> None:  # type: ignore[no-untyped-def]
    configure_logging(level="INFO")
    log = structlog.get_logger()

    bind_request_id("req-123")
    try:
        log.info("inside_request")
    finally:
        clear_request_id()
    log.info("outside_request")

    captured = capsys.readouterr()
    lines = [json.loads(line) for line in captured.out.strip().splitlines() if line]
    inside = next(p for p in lines if p["event"] == "inside_request")
    outside = next(p for p in lines if p["event"] == "outside_request")
    assert inside["request_id"] == "req-123"
    assert "request_id" not in outside


def test_configure_logging_is_idempotent() -> None:
    """Calling configure_logging twice should not duplicate handlers."""
    configure_logging(level="INFO")
    handler_count_first = len(logging.getLogger().handlers)
    configure_logging(level="INFO")
    handler_count_second = len(logging.getLogger().handlers)
    assert handler_count_first == handler_count_second
