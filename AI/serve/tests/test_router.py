import io
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd
import pytest
from fastapi.testclient import TestClient

from AI.serve.main import build_app


@pytest.fixture
def client(onnx_path: Path) -> TestClient:
    app = build_app()
    return TestClient(app)


def test_health_returns_ok(client: TestClient) -> None:
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["model_loaded"] is True


def test_run_endpoint_accepts_synthetic(
    client: TestClient, synthetic_capture_bytes: bytes
) -> None:
    resp = client.post(
        "/api/v1/ml-demo/run",
        files={"capture": ("synthetic.zip", synthetic_capture_bytes, "application/zip")},
    )
    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["calibration"]["duration_seconds"] == 180
    assert len(body["chunks"]) >= 1
    assert body["model"]["target_hz"] == 25


def test_run_endpoint_rejects_missing_file(client: TestClient, tmp_path: Path) -> None:
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("ppg_green.csv", "timestamp_ms,ppg_green\n1,1.0\n")
    resp = client.post(
        "/api/v1/ml-demo/run",
        files={"capture": ("bad.zip", bad.read_bytes(), "application/zip")},
    )
    assert resp.status_code == 400
    assert "eda.csv" in resp.json()["detail"]


def test_run_endpoint_rejects_oversize(
    client: TestClient, monkeypatch
) -> None:
    monkeypatch.setenv("ML_DEMO_MAX_UPLOAD_BYTES", "100")
    # Need to rebuild app for env to take effect
    app = build_app()
    local_client = TestClient(app)
    resp = local_client.post(
        "/api/v1/ml-demo/run",
        files={"capture": ("big.zip", b"x" * 1024, "application/zip")},
    )
    assert resp.status_code == 413


def test_run_endpoint_rejects_short_recording(client: TestClient) -> None:
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
    resp = client.post(
        "/api/v1/ml-demo/run",
        files={"capture": ("short.zip", buf.getvalue(), "application/zip")},
    )
    assert resp.status_code == 400
    assert "too short" in resp.json()["detail"].lower()
