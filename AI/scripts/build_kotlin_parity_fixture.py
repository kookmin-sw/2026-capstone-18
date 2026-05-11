#!/usr/bin/env python3
"""Build galaxy_test.zip into the Android test resources from AI/data/raw/Galaxy_Test/.

The Galaxy_Test/ directory is gitignored. This script is a no-op if the raw data
isn't present — same convention as AI/serve/tests/conftest.py.
"""
from __future__ import annotations

import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
SRC = REPO_ROOT / "AI" / "data" / "raw" / "Galaxy_Test"
DST = REPO_ROOT / "frontend" / "android" / "app" / "src" / "test" / "resources" / "galaxy_test.zip"
NEEDED = ("ppg_green.csv", "eda.csv", "accel.csv")


def main() -> int:
    if not SRC.exists():
        print(f"[skip] Galaxy_Test source not present at {SRC}", file=sys.stderr)
        return 0
    missing = [n for n in NEEDED if not (SRC / n).exists()]
    if missing:
        print(f"[skip] missing {missing} in {SRC}", file=sys.stderr)
        return 0
    DST.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zf:
        for name in NEEDED:
            zf.write(SRC / name, arcname=name)
    print(f"[ok] wrote {DST} ({DST.stat().st_size:,} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
