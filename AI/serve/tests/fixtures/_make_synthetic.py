"""Generate a deterministic synthetic Galaxy-style capture zip for unit tests.

Run from the repo root once:
    python AI/serve/tests/fixtures/_make_synthetic.py

Produces synthetic_capture.zip in this directory. Commit the zip; do not
regenerate as part of CI (the goal is reproducible test inputs).
"""
from __future__ import annotations

import io
import zipfile
from pathlib import Path

import numpy as np
import pandas as pd

DURATION_SEC = 360  # 6 minutes — covers the 300 s buffer plus one chunk
PPG_HZ = 25
ACC_HZ = 25
EDA_HZ = 1
START_TS_MS = 1_700_000_000_000


def _ppg_frame() -> pd.DataFrame:
    n = DURATION_SEC * PPG_HZ
    t = np.arange(n) / PPG_HZ
    rng = np.random.default_rng(seed=1)
    signal = 1000.0 + 50.0 * np.sin(2 * np.pi * 1.2 * t) + rng.normal(0, 5.0, n)
    return pd.DataFrame(
        {
            "timestamp_ms": (START_TS_MS + (t * 1000).astype(np.int64)),
            "ppg_green": signal.astype(np.float32),
        }
    )


def _eda_frame() -> pd.DataFrame:
    n = DURATION_SEC * EDA_HZ
    t = np.arange(n) / EDA_HZ
    rng = np.random.default_rng(seed=2)
    signal = 5.0 + 0.1 * np.sin(2 * np.pi * 0.01 * t) + rng.normal(0, 0.05, n)
    return pd.DataFrame(
        {
            "timestamp_ms": (START_TS_MS + (t * 1000).astype(np.int64)),
            "skin_conductance": signal.astype(np.float32),
        }
    )


def _accel_frame() -> pd.DataFrame:
    n = DURATION_SEC * ACC_HZ
    t = np.arange(n) / ACC_HZ
    rng = np.random.default_rng(seed=3)
    return pd.DataFrame(
        {
            "timestamp_ms": (START_TS_MS + (t * 1000).astype(np.int64)),
            "x": rng.normal(0, 0.1, n).astype(np.float32),
            "y": rng.normal(0, 0.1, n).astype(np.float32),
            "z": (1.0 + rng.normal(0, 0.05, n)).astype(np.float32),
        }
    )


def main() -> None:
    out = Path(__file__).parent / "synthetic_capture.zip"
    frames = {
        "ppg_green.csv": _ppg_frame(),
        "eda.csv": _eda_frame(),
        "accel.csv": _accel_frame(),
    }
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as zf:
        for name, df in frames.items():
            zf.writestr(name, df.to_csv(index=False))
    out.write_bytes(buf.getvalue())
    print(f"wrote {out} ({out.stat().st_size} bytes)")


if __name__ == "__main__":
    main()
