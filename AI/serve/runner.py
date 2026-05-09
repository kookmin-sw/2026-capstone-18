"""Drive RealTimeStressPipeline through synced signals and collect per-chunk results.

The chunk loop mirrors `simulate_live_stream` in AI/src/pipeline.py — extracted
so we can capture results into a list instead of printing.
"""
from __future__ import annotations

from pathlib import Path

from AI.serve.preprocess import SyncedSignals
from AI.serve.schemas import ChunkResult
from AI.src.pipeline import (
    BASELINE_STEPS,
    BUFFER_STEPS,
    CHUNK_STEPS,
    TARGET_HZ,
    RealTimeStressPipeline,
)


class RunnerError(ValueError):
    """Raised when the runner cannot produce any inference chunks."""


def run_pipeline(synced: SyncedSignals, onnx_path: Path) -> list[ChunkResult]:
    if len(synced.ppg_smooth) < BUFFER_STEPS:
        raise RunnerError(
            f"recording too short: need at least {BUFFER_STEPS / TARGET_HZ:.0f}s, "
            f"got {len(synced.ppg_smooth) / TARGET_HZ:.1f}s"
        )

    pipeline = RealTimeStressPipeline(str(onnx_path))
    pipeline.calibrate(
        synced.ppg_smooth[:BASELINE_STEPS],
        synced.eda[:BASELINE_STEPS],
        synced.acc_mag[:BASELINE_STEPS],
    )

    results: list[ChunkResult] = []
    for current_step in range(BUFFER_STEPS, len(synced.ppg_smooth), CHUNK_STEPS):
        current_time_sec = current_step / TARGET_HZ
        buffer_start = current_step - BUFFER_STEPS
        notif, prob = pipeline.process_buffer(
            synced.ppg_smooth[buffer_start:current_step],
            synced.eda[buffer_start:current_step],
            synced.acc_mag[buffer_start:current_step],
            current_time_sec,
        )
        results.append(
            ChunkResult(
                time_seconds=int(current_time_sec),
                time_label=f"{int(current_time_sec // 60)}m {int(current_time_sec % 60):02d}s",
                prob_stress=float(prob),
                state="STRESS_EVENT" if pipeline.is_in_stress_event else "Baseline",
                should_notify=bool(notif),
                in_stress_event=bool(pipeline.is_in_stress_event),
            )
        )
    return results
