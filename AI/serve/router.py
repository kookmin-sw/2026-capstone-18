"""HTTP routes for the ML demo service."""
from __future__ import annotations

from pathlib import Path

from fastapi import APIRouter, File, HTTPException, UploadFile

from AI.serve.preprocess import PreprocessError, preprocess_capture_zip
from AI.serve.runner import RunnerError, run_pipeline
from AI.serve.schemas import CalibrationInfo, ModelInfo, RunResponse
from AI.serve.settings import Settings
from AI.src.pipeline import (
    BASELINE_SEC,
    BASELINE_STEPS,
    BUFFER_SEC,
    CHUNK_SEC,
    TARGET_HZ,
)

router = APIRouter()


def _settings() -> Settings:
    return Settings()


@router.get("/health")
async def health() -> dict[str, object]:
    settings = _settings()
    return {"status": "ok", "model_loaded": settings.onnx_path.exists()}


@router.post("/api/v1/ml-demo/run", response_model=RunResponse)
async def run(capture: UploadFile = File(...)) -> RunResponse:
    settings = _settings()
    blob = await capture.read()
    if len(blob) > settings.max_upload_bytes:
        raise HTTPException(
            status_code=413,
            detail=f"upload exceeds {settings.max_upload_bytes} bytes",
        )

    try:
        synced = preprocess_capture_zip(blob)
    except PreprocessError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    try:
        chunks = run_pipeline(synced, settings.onnx_path)
    except RunnerError as e:
        raise HTTPException(status_code=400, detail=str(e)) from e

    return RunResponse(
        calibration=CalibrationInfo(
            duration_seconds=BASELINE_SEC,
            samples_used=BASELINE_STEPS,
        ),
        chunks=chunks,
        model=ModelInfo(
            onnx_path=str(_relative_onnx(settings.onnx_path)),
            target_hz=TARGET_HZ,
            chunk_seconds=CHUNK_SEC,
            buffer_seconds=BUFFER_SEC,
        ),
    )


def _relative_onnx(path: Path) -> Path:
    try:
        return path.relative_to(Path.cwd())
    except ValueError:
        return path
