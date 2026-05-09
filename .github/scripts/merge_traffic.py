"""Merge a fresh GitHub traffic API response into a date-keyed JSON file.

GitHub's `/traffic/views` and `/traffic/clones` endpoints return only the last
14 days. This script merges each daily entry into a persistent JSON file keyed
by ISO timestamp so we keep a rolling history beyond the API window.

Usage:
    python merge_traffic.py <kind> <api_response.json>

Where <kind> is "views" or "clones". The kind doubles as the inner array key
on the API response and as the output filename under .github/traffic/.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path


def main() -> int:
    kind = sys.argv[1]
    new_payload = json.loads(Path(sys.argv[2]).read_text())

    out_path = Path(f".github/traffic/{kind}.json")
    out_path.parent.mkdir(parents=True, exist_ok=True)

    existing = json.loads(out_path.read_text()) if out_path.exists() else {}

    for entry in new_payload.get(kind, []):
        ts = entry["timestamp"]
        # API values within the 14-day window are cumulative-for-that-day and
        # only ever grow during the day. Take max so a partial mid-day snapshot
        # never overwrites a complete final value from a later run.
        prior = existing.get(ts, {"count": 0, "uniques": 0})
        existing[ts] = {
            "count": max(prior["count"], entry["count"]),
            "uniques": max(prior["uniques"], entry["uniques"]),
        }

    out_path.write_text(json.dumps(dict(sorted(existing.items())), indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
