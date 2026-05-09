"""Shared test fixtures for the ML demo service."""
from __future__ import annotations

from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[3]
GALAXY_TEST_DIR = REPO_ROOT / "AI" / "data" / "raw" / "Galaxy_Test"
ONNX_PATH = REPO_ROOT / "AI" / "checkpoints_final" / "wesad_w2.0" / "wesad_mamba_v1.onnx"
SYNTHETIC_ZIP = Path(__file__).parent / "fixtures" / "synthetic_capture.zip"


@pytest.fixture
def synthetic_capture_bytes() -> bytes:
    return SYNTHETIC_ZIP.read_bytes()


@pytest.fixture
def galaxy_test_zip_bytes() -> bytes:
    """Galaxy_Test bundled as a zip in memory; skips if fixture absent."""
    if not GALAXY_TEST_DIR.exists():
        pytest.skip("Galaxy_Test fixture not present (data/ is gitignored)")
    import io
    import zipfile

    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name in ("ppg_green.csv", "eda.csv", "accel.csv"):
            path = GALAXY_TEST_DIR / name
            if not path.exists():
                pytest.skip(f"Galaxy_Test missing {name}")
            zf.write(path, arcname=name)
    return buf.getvalue()


@pytest.fixture
def onnx_path() -> Path:
    if not ONNX_PATH.exists():
        pytest.skip(f"ONNX model not present at {ONNX_PATH}")
    return ONNX_PATH
