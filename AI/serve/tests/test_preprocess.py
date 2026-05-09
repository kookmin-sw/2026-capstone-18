import zipfile
from pathlib import Path

import numpy as np
import pytest

from AI.serve.preprocess import PreprocessError, SyncedSignals, preprocess_capture_zip

FIXTURE = Path(__file__).parent / "fixtures" / "synthetic_capture.zip"
TARGET_HZ = 25
SYNTHETIC_DURATION_SEC = 360  # generator's nominal duration


def test_preprocess_returns_synced_signals() -> None:
    with FIXTURE.open("rb") as f:
        synced = preprocess_capture_zip(f.read())
    assert isinstance(synced, SyncedSignals)
    # Synced length is determined by the smallest channel's overlap window
    # (EDA at 1 Hz spans 359 s for a 360-sample fixture), then resampled at 25 Hz.
    # Assert the three arrays line up and the duration is in the expected ballpark.
    assert len(synced.ppg_smooth) == len(synced.eda) == len(synced.acc_mag)
    assert len(synced.ppg_smooth) >= TARGET_HZ * (SYNTHETIC_DURATION_SEC - 2)
    assert len(synced.ppg_smooth) <= TARGET_HZ * (SYNTHETIC_DURATION_SEC + 1)
    assert SYNTHETIC_DURATION_SEC - 2 <= synced.duration_seconds <= SYNTHETIC_DURATION_SEC
    assert synced.ppg_smooth.dtype == np.float64
    assert np.isfinite(synced.ppg_smooth).all()
    assert np.isfinite(synced.eda).all()
    assert (synced.acc_mag >= 0).all()


def test_preprocess_rejects_zip_missing_csv(tmp_path: Path) -> None:
    bad = tmp_path / "bad.zip"
    with zipfile.ZipFile(bad, "w") as zf:
        zf.writestr("ppg_green.csv", "timestamp_ms,ppg_green\n1,1.0\n")
        # missing eda.csv and accel.csv
    with pytest.raises(PreprocessError) as exc:
        preprocess_capture_zip(bad.read_bytes())
    assert "eda.csv" in str(exc.value)


def test_preprocess_rejects_non_zip() -> None:
    with pytest.raises(PreprocessError):
        preprocess_capture_zip(b"not a zip")
