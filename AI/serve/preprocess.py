"""Convert a Galaxy capture zip into 25 Hz synchronized signal arrays.

Logic mirrors the preprocessing block of `simulate_live_stream` in
AI/src/pipeline.py — extracted so the pipeline file stays untouched.
"""
from __future__ import annotations

import io
import zipfile
from dataclasses import dataclass

import numpy as np
import pandas as pd
from scipy import signal as sp_signal
from scipy.interpolate import interp1d

from AI.src.pipeline import TARGET_HZ

_REQUIRED = ("ppg_green.csv", "eda.csv", "accel.csv")


class PreprocessError(ValueError):
    """Raised when an upload cannot be turned into synced signals."""


@dataclass(frozen=True)
class SyncedSignals:
    ppg_smooth: np.ndarray
    eda: np.ndarray
    acc_mag: np.ndarray
    duration_seconds: float


def preprocess_capture_zip(blob: bytes) -> SyncedSignals:
    try:
        zf = zipfile.ZipFile(io.BytesIO(blob))
    except zipfile.BadZipFile as e:
        raise PreprocessError(f"upload is not a valid zip: {e}") from e

    names = set(zf.namelist())
    for required in _REQUIRED:
        if required not in names:
            raise PreprocessError(f"missing {required} in upload")

    df_ppg = _read_csv(zf, "ppg_green.csv", ["timestamp_ms", "ppg_green"])
    df_eda = _read_csv(zf, "eda.csv", ["timestamp_ms", "skin_conductance"])
    df_acc = _read_csv(zf, "accel.csv", ["timestamp_ms", "x", "y", "z"])

    t0_ms = max(
        df_ppg["timestamp_ms"].iloc[0],
        df_eda["timestamp_ms"].iloc[0],
        df_acc["timestamp_ms"].iloc[0],
    )
    t_end_ms = min(
        df_ppg["timestamp_ms"].iloc[-1],
        df_eda["timestamp_ms"].iloc[-1],
        df_acc["timestamp_ms"].iloc[-1],
    )
    if t_end_ms <= t0_ms:
        raise PreprocessError("captures do not overlap in time")

    duration = (t_end_ms - t0_ms) / 1000.0
    target_times = np.arange(0, duration, 1.0 / TARGET_HZ)

    ppg_raw = interp1d(
        (df_ppg["timestamp_ms"] - t0_ms) / 1000.0,
        df_ppg["ppg_green"],
        kind="linear",
        fill_value="extrapolate",
    )(target_times)
    eda_raw = interp1d(
        (df_eda["timestamp_ms"] - t0_ms) / 1000.0,
        df_eda["skin_conductance"],
        kind="previous",
        fill_value="extrapolate",
    )(target_times)
    acc_x = interp1d(
        (df_acc["timestamp_ms"] - t0_ms) / 1000.0,
        df_acc["x"],
        kind="linear",
        fill_value="extrapolate",
    )(target_times)
    acc_y = interp1d(
        (df_acc["timestamp_ms"] - t0_ms) / 1000.0,
        df_acc["y"],
        kind="linear",
        fill_value="extrapolate",
    )(target_times)
    acc_z = interp1d(
        (df_acc["timestamp_ms"] - t0_ms) / 1000.0,
        df_acc["z"],
        kind="linear",
        fill_value="extrapolate",
    )(target_times)

    b, a = sp_signal.butter(
        4,
        [0.1 / (0.5 * TARGET_HZ), 10.0 / (0.5 * TARGET_HZ)],
        btype="bandpass",
        analog=False,
    )
    ppg_smooth = sp_signal.filtfilt(b, a, ppg_raw)
    ppg_smooth = sp_signal.savgol_filter(ppg_smooth, window_length=5, polyorder=2)
    acc_mag = np.sqrt(acc_x**2 + acc_y**2 + acc_z**2)

    return SyncedSignals(
        ppg_smooth=ppg_smooth,
        eda=eda_raw,
        acc_mag=acc_mag,
        duration_seconds=duration,
    )


def _read_csv(zf: zipfile.ZipFile, name: str, expected_columns: list[str]) -> pd.DataFrame:
    with zf.open(name) as fh:
        df = pd.read_csv(fh)
    missing = [c for c in expected_columns if c not in df.columns]
    if missing:
        raise PreprocessError(f"{name} missing columns: {missing}")
    return df
