import zipfile
from pathlib import Path

FIXTURE = Path(__file__).parent / "fixtures" / "synthetic_capture.zip"


def test_synthetic_capture_zip_contains_expected_csvs() -> None:
    with zipfile.ZipFile(FIXTURE) as zf:
        names = set(zf.namelist())
    assert names == {"ppg_green.csv", "eda.csv", "accel.csv"}
