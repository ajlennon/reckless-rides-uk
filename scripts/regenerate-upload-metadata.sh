#!/usr/bin/env bash
# Regenerate *_UPLOAD.json for an existing incident (from manifest + channel templates).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: regenerate-upload-metadata.sh DEB-20260623T080303Z_53.4092N_2.9778W_001}"

MANIFEST="$ROOT/register/manifests/${BASE}_MANIFEST.json"
[[ -f "$MANIFEST" ]] || { echo "Missing manifest: $MANIFEST" >&2; exit 1; }

ROOT="$ROOT" python3 - "$MANIFEST" <<'PY'
import json, os, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
manifest = json.loads(Path(sys.argv[1]).read_text())
base = manifest["base_name"]
proc_dir = root / "evidence" / "processed"
upload_path = proc_dir / f"{base}_UPLOAD.json"

def read_channel(name: str) -> str:
    p = root / "channel" / name
    return p.read_text().strip() if p.is_file() else ""

default_tags = [t.strip() for t in read_channel("upload-tags.txt").split(",") if t.strip()]
footer = read_channel("video-description-footer.txt")

loc = manifest["location"]
lat, lon = loc.get("latitude", ""), loc.get("longitude", "")
lat_tag = loc.get("label", "").split("_")[0] if loc.get("label") else ""
lon_tag = loc.get("label", "").split("_")[1] if loc.get("label") and "_" in loc["label"] else ""
utc_recorded = manifest["recorded_utc"]
bst_recorded = manifest.get("recorded_bst", "")
if not bst_recorded and utc_recorded:
    import subprocess
    try:
        bst_recorded = subprocess.check_output(
            ["bash", "-c", f"TZ=Europe/London date -d '{utc_recorded}' '+%Y-%m-%d %H:%M:%S %Z'"],
            text=True,
        ).strip()
    except Exception:
        pass
notes = manifest.get("notes", "")
pub_path = manifest["files"]["publish"]["path"]
proc_path = manifest["files"]["processed"]["path"]
device = manifest.get("source_device", {}).get("model", "")

map_url = f"https://www.google.com/maps?q={lat},{lon}" if lat and lon else ""
title = f"Pavement e-bike — {bst_recorded}" if bst_recorded else f"Pavement e-bike — {utc_recorded}"

description_parts = [
    "Incident log (evidence archive)",
    "",
    f"Recorded: {utc_recorded}" + (f" ({bst_recorded})" if bst_recorded else ""),
]
if lat and lon:
    hem = "W" if lon_tag.endswith("W") else "E"
    description_parts += [f"GPS: {lat}°N, {lon}°{hem}", f"Map: {map_url}"]
if device:
    description_parts.append(f"Device: {device}")
if notes:
    description_parts += ["", f"Notes: {notes}"]
description_parts += ["", "Police report: [pending]", "", footer]

upload = {
    "schema": "dangerous-ebikers-youtube-upload/v1",
    "incident_id": manifest["incident_id"],
    "base_name": base,
    "files": {"upload_video": pub_path, "processed_video": proc_path},
    "youtube": {
        "title": title,
        "description": "\n".join(description_parts),
        "tags": default_tags,
        "privacy": "unlisted",
        "categoryId": "22",
        "madeForKids": False,
        "playlist": "2026 Incidents",
    },
    "incident": {
        "recorded_utc": utc_recorded,
        "recorded_bst": bst_recorded,
        "latitude": lat,
        "longitude": lon,
        "location_label": loc.get("label", ""),
        "map_url": map_url,
        "device": device,
    },
    "police_ref": manifest.get("police_ref", ""),
    "youtube_url": manifest.get("youtube_url", ""),
    "notes": notes,
}
upload_path.write_text(json.dumps(upload, indent=2) + "\n")
print(f"Wrote {upload_path}")
PY
