"""Pydantic request/response models for the ML demo service."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, Field

State = Literal["Baseline", "STRESS_EVENT"]


class ChunkResult(BaseModel):
    time_seconds: int = Field(..., description="Inference timestamp from start of recording.")
    time_label: str = Field(..., description="Human-friendly label, e.g. '5m 00s'.")
    prob_stress: float = Field(..., ge=0.0, le=1.0)
    state: State
    should_notify: bool
    in_stress_event: bool


class CalibrationInfo(BaseModel):
    duration_seconds: int
    samples_used: int


class ModelInfo(BaseModel):
    onnx_path: str
    target_hz: int
    chunk_seconds: int
    buffer_seconds: int


class RunResponse(BaseModel):
    calibration: CalibrationInfo
    chunks: list[ChunkResult]
    model: ModelInfo
