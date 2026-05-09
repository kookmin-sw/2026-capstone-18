from pathlib import Path

import pytest

from AI.serve.preprocess import preprocess_capture_zip
from AI.serve.runner import RunnerError, run_pipeline

EXPECTED_GALAXY_PROBS = [0.441, 0.691, 0.450, 0.289, 0.280]
PARITY_TOL = 0.01


def test_runner_smoke_synthetic(synthetic_capture_bytes: bytes, onnx_path: Path) -> None:
    synced = preprocess_capture_zip(synthetic_capture_bytes)
    chunks = run_pipeline(synced, onnx_path)
    assert len(chunks) >= 1
    for chunk in chunks:
        assert 0.0 <= chunk.prob_stress <= 1.0
        assert chunk.state in ("Baseline", "STRESS_EVENT")
        assert "m" in chunk.time_label and "s" in chunk.time_label


def test_runner_rejects_too_short(onnx_path: Path) -> None:
    """A 1-minute recording cannot satisfy the 300 s buffer."""
    import io
    import zipfile

    import numpy as np
    import pandas as pd

    duration_sec = 60
    target_hz = 25
    n = duration_sec * target_hz
    t_ms = (np.arange(n) / target_hz * 1000).astype(np.int64) + 1_700_000_000_000

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w") as zf:
        zf.writestr(
            "ppg_green.csv",
            pd.DataFrame({"timestamp_ms": t_ms, "ppg_green": np.ones(n)}).to_csv(index=False),
        )
        zf.writestr(
            "eda.csv",
            pd.DataFrame({"timestamp_ms": t_ms[::25], "skin_conductance": np.ones(n // 25)})
            .to_csv(index=False),
        )
        zf.writestr(
            "accel.csv",
            pd.DataFrame(
                {"timestamp_ms": t_ms, "x": np.zeros(n), "y": np.zeros(n), "z": np.ones(n)}
            ).to_csv(index=False),
        )
    synced = preprocess_capture_zip(buf.getvalue())
    with pytest.raises(RunnerError) as exc:
        run_pipeline(synced, onnx_path)
    assert "too short" in str(exc.value).lower()


def test_runner_parity_with_galaxy_test(
    galaxy_test_zip_bytes: bytes, onnx_path: Path
) -> None:
    """End-to-end parity: outputs must match expected_pipeline_log.txt within 1e-2."""
    synced = preprocess_capture_zip(galaxy_test_zip_bytes)
    chunks = run_pipeline(synced, onnx_path)
    assert len(chunks) == len(EXPECTED_GALAXY_PROBS), (
        f"expected {len(EXPECTED_GALAXY_PROBS)} chunks, got {len(chunks)}"
    )
    for i, (chunk, expected) in enumerate(zip(chunks, EXPECTED_GALAXY_PROBS, strict=True)):
        assert abs(chunk.prob_stress - expected) < PARITY_TOL, (
            f"chunk {i}: prob {chunk.prob_stress:.3f} not within {PARITY_TOL} of {expected:.3f}"
        )
        assert chunk.state == "Baseline"
        assert chunk.should_notify is False
