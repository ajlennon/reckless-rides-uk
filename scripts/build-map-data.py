#!/usr/bin/env python3
"""Build public GeoJSON for the GitHub Pages incident map from *_UPLOAD.json."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CORE = ROOT / "core"
sys.path.insert(0, str(CORE))

from evidence_core.geojson import write_geojson  # noqa: E402

PROCESSED = ROOT / "evidence" / "processed"
OUT = ROOT / "docs" / "data" / "incidents.geojson"


def main() -> int:
    count = write_geojson(
        PROCESSED,
        OUT,
        require_youtube_url=True,
        require_public_youtube=True,
    )
    print(f"Wrote {count} incident(s) -> {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
