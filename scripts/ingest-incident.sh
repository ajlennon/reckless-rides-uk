#!/usr/bin/env bash
# Ingest a Meta glasses clip: archive original, blur faces, strip metadata, log for police handover.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:?Usage: ingest-incident.sh /path/to/source.MOV [notes...]}"

NOTES="${*:2}"
DEFACE="${DEFACE:-$HOME/.local/bin/deface}"
FFMPEG="${FFMPEG:-ffmpeg}"
FFPROBE="${FFPROBE:-ffprobe}"

for bin in "$FFPROBE" "$FFMPEG"; do
  command -v "$bin" >/dev/null || { echo "Missing: $bin" >&2; exit 1; }
done
command -v "$DEFACE" >/dev/null || { echo "Missing deface — run: pip3 install --user deface" >&2; exit 1; }
command -v python3 >/dev/null || { echo "Missing: python3" >&2; exit 1; }

ORIG_DIR="$ROOT/evidence/originals"
PROC_DIR="$ROOT/evidence/processed"
PUB_DIR="$ROOT/evidence/publish"
MANIFEST_DIR="$ROOT/register/manifests"
REGISTER="$ROOT/register/incidents.csv"

mkdir -p "$ORIG_DIR" "$PROC_DIR" "$PUB_DIR" "$MANIFEST_DIR"

if [[ ! -f "$REGISTER" ]]; then
  echo "incident_id,utc_recorded,bst_recorded,latitude,longitude,original_filename,processed_filename,publish_filename,sha256_original,ingested_utc,police_ref,youtube_url,notes" >"$REGISTER"
fi

META_JSON="$(FFPROBE="$FFPROBE" python3 - "$SRC" <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timezone

try:
    from zoneinfo import ZoneInfo
except ImportError:
    ZoneInfo = None

src = sys.argv[1]
ffprobe = os.environ["FFPROBE"]
out = subprocess.check_output(
    [ffprobe, "-v", "quiet", "-show_entries", "format_tags", "-of", "json", src],
    text=True,
)
tags = json.loads(out).get("format", {}).get("tags", {})
utc_raw = tags.get("com.apple.quicktime.creationdate") or tags.get("creation_time") or ""
utc_raw = utc_raw.rstrip("Z")
if utc_raw.endswith(".000000"):
    utc_raw = utc_raw[:-7]
dt_utc = datetime.strptime(utc_raw, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=timezone.utc)
iso6709 = tags.get("com.apple.quicktime.location.ISO6709", "")
lat = lon = lat_tag = lon_tag = ""
import re
m = re.match(r"\+([0-9.]+)-([0-9.]+)/?", iso6709)
if m:
    lat_val = float(m.group(1))
    lon_val = -float(m.group(2))  # Meta ISO6709: hyphen separates west longitude
    lat = f"{lat_val:.4f}"
    lon = f"{abs(lon_val):.4f}"
    lat_tag = f"{lat}N"
    lon_tag = f"{lon}W" if lon_val < 0 else f"{lon}E"
else:
    lat_tag = lon_tag = "UNKNOWN"
bst = ""
if ZoneInfo:
    bst = dt_utc.astimezone(ZoneInfo("Europe/London")).strftime("%Y-%m-%d %H:%M:%S %Z")
print(json.dumps({
    "utc_recorded": dt_utc.strftime("%Y-%m-%dT%H:%M:%SZ"),
    "utc_stamp": dt_utc.strftime("%Y%m%dT%H%M%SZ"),
    "bst_recorded": bst,
    "latitude": lat,
    "longitude": lon,
    "lat_tag": lat_tag,
    "lon_tag": lon_tag,
    "device": tags.get("com.apple.quicktime.model", ""),
    "device_comment": tags.get("com.apple.quicktime.comment", ""),
}))
PY
)"

UTC_RECORDED="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['utc_recorded'])")"
UTC_STAMP="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['utc_stamp'])")"
BST_RECORDED="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['bst_recorded'])")"
if [[ -z "$BST_RECORDED" && -n "$UTC_RECORDED" ]]; then
  BST_RECORDED="$(TZ=Europe/London date -d "${UTC_RECORDED/+00:00/Z}" '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)"
fi
LAT="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['latitude'])")"
LON="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['longitude'])")"
LAT_TAG="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['lat_tag'])")"
LON_TAG="$(echo "$META_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin)['lon_tag'])")"

NEXT_ID="$(python3 - "$REGISTER" <<'PY'
import csv, sys
path = sys.argv[1]
try:
    with open(path, newline="") as f:
        rows = list(csv.DictReader(f))
except FileNotFoundError:
    rows = []
nums = [int(r["incident_id"]) for r in rows if r.get("incident_id", "").isdigit()]
print(f"{max(nums, default=0) + 1:03d}")
PY
)"

BASE="DEB-${UTC_STAMP}_${LAT_TAG}_${LON_TAG}_${NEXT_ID}"
EXT="${SRC##*.}"
EXT_LOWER="$(printf '%s' "$EXT" | tr '[:upper:]' '[:lower:]')"

ORIG_FILE="${BASE}_ORIGINAL.${EXT_LOWER}"
PROC_FILE="${BASE}_PROCESSED.mp4"
PUB_FILE="${BASE}_PUBLISH.mp4"
UPLOAD_META_FILE="${BASE}_UPLOAD.json"
MANIFEST_FILE="${MANIFEST_DIR}/${BASE}_MANIFEST.json"

ORIG_PATH="$ORIG_DIR/$ORIG_FILE"
PROC_PATH="$PROC_DIR/$PROC_FILE"
PUB_PATH="$PUB_DIR/$PUB_FILE"
UPLOAD_META_PATH="$PROC_DIR/$UPLOAD_META_FILE"

if [[ -e "$ORIG_PATH" ]]; then
  echo "Refusing to overwrite existing original: $ORIG_PATH" >&2
  exit 1
fi

echo "Incident $NEXT_ID - $BASE"
cp -a -- "$SRC" "$ORIG_PATH"

SHA256_ORIG="$(sha256sum "$ORIG_PATH" | awk '{print $1}')"
INGESTED_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Blurring faces -> processed/"
"$DEFACE" "$ORIG_PATH" --replacewith blur --mask-scale 1.3 --keep-audio -o "$PROC_PATH"

echo "Stripping metadata -> publish/"
"$FFMPEG" -y -loglevel error -i "$PROC_PATH" -c copy -map_metadata -1 "$PUB_PATH"

SHA256_PROC="$(sha256sum "$PROC_PATH" | awk '{print $1}')"
SHA256_PUB="$(sha256sum "$PUB_PATH" | awk '{print $1}')"

META_JSON="$META_JSON" NOTES="$NOTES" UPLOAD_META_PATH="$UPLOAD_META_PATH" python3 - "$MANIFEST_FILE" "$NEXT_ID" "$BASE" \
  "$UTC_RECORDED" "$BST_RECORDED" "$LAT" "$LON" "$LAT_TAG" "$LON_TAG" \
  "$ORIG_PATH" "$PROC_PATH" "$PUB_PATH" \
  "$SHA256_ORIG" "$SHA256_PROC" "$SHA256_PUB" "$INGESTED_UTC" <<'PY'
import json, os, sys

meta = json.loads(os.environ["META_JSON"])
(
    manifest_path, incident_id, base_name,
    utc_recorded, bst_recorded, lat, lon, lat_tag, lon_tag,
    orig_path, proc_path, pub_path,
    sha_orig, sha_proc, sha_pub, ingested_utc,
) = sys.argv[1:]

manifest = {
    "schema": "dangerous-ebikers-evidence/v1",
    "incident_id": incident_id,
    "base_name": base_name,
    "recorded_utc": utc_recorded,
    "recorded_bst": bst_recorded,
    "location": {
        "latitude": lat,
        "longitude": lon,
        "label": f"{lat_tag}_{lon_tag}",
    },
    "source_device": {
        "model": meta.get("device", ""),
        "comment": meta.get("device_comment", ""),
    },
    "files": {
        "original": {"path": orig_path, "sha256": sha_orig, "role": "POLICE_EVIDENCE"},
        "processed": {"path": proc_path, "sha256": sha_proc, "role": "INTERNAL_REVIEW"},
        "publish": {"path": pub_path, "sha256": sha_pub, "role": "YOUTUBE_UPLOAD"},
        "upload_metadata": {"path": os.environ.get("UPLOAD_META_PATH", ""), "role": "YOUTUBE_METADATA"},
    },
    "processing": {
        "ingested_utc": ingested_utc,
        "face_blur": "deface --replacewith blur --mask-scale 1.3",
        "metadata_stripped_on_publish": True,
    },
    "police_ref": "",
    "youtube_url": "",
    "notes": os.environ.get("NOTES", ""),
}
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

ROOT="$ROOT" META_JSON="$META_JSON" NOTES="$NOTES" python3 - "$UPLOAD_META_PATH" "$NEXT_ID" "$BASE" \
  "$UTC_RECORDED" "$BST_RECORDED" "$LAT" "$LON" "$LAT_TAG" "$LON_TAG" \
  "$PUB_PATH" "$PROC_PATH" <<'PY'
import json, os, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
meta = json.loads(os.environ["META_JSON"])
(
    upload_path, incident_id, base_name,
    utc_recorded, bst_recorded, lat, lon, lat_tag, lon_tag,
    pub_path, proc_path,
) = sys.argv[1:]

def read_channel(name: str) -> str:
    p = root / "channel" / name
    return p.read_text().strip() if p.is_file() else ""

default_tags = [t.strip() for t in read_channel("upload-tags.txt").split(",") if t.strip()]
footer = read_channel("video-description-footer.txt")

map_url = f"https://www.google.com/maps?q={lat},{lon}" if lat and lon else ""
bst_short = bst_recorded or utc_recorded
title = f"Pavement e-bike — {bst_short}" if bst_recorded else f"Pavement e-bike — {utc_recorded}"

description_parts = [
    "Incident log (evidence archive)",
    "",
    f"Recorded: {utc_recorded}" + (f" ({bst_recorded})" if bst_recorded else ""),
]
if lat and lon:
    hem = "W" if lon_tag.endswith("W") else "E"
    description_parts += [
        f"GPS: {lat}°N, {lon}°{hem}",
        f"Map: {map_url}",
    ]
if meta.get("device"):
    description_parts.append(f"Device: {meta['device']}")
if os.environ.get("NOTES"):
    description_parts += ["", f"Notes: {os.environ['NOTES']}"]
description_parts += [
    "",
    "Police report: [pending]",
    "",
    footer,
]
description = "\n".join(description_parts)

upload = {
    "schema": "dangerous-ebikers-youtube-upload/v1",
    "incident_id": incident_id,
    "base_name": base_name,
    "files": {
        "upload_video": pub_path,
        "processed_video": proc_path,
    },
    "youtube": {
        "title": title,
        "description": description,
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
        "location_label": f"{lat_tag}_{lon_tag}",
        "map_url": map_url,
        "device": meta.get("device", ""),
    },
    "police_ref": "",
    "youtube_url": "",
    "notes": os.environ.get("NOTES", ""),
}
Path(upload_path).write_text(json.dumps(upload, indent=2) + "\n")
PY

NOTES_CSV="$(printf '%s' "$NOTES" | tr '\n' ' ' | sed 's/"/""/g')"
echo "\"$NEXT_ID\",\"$UTC_RECORDED\",\"$BST_RECORDED\",\"$LAT\",\"$LON\",\"$ORIG_FILE\",\"$PROC_FILE\",\"$PUB_FILE\",\"$SHA256_ORIG\",\"$INGESTED_UTC\",\"\",\"\",\"$NOTES_CSV\"" >>"$REGISTER"

cat <<EOF

Ingest complete.

  Incident ID : $NEXT_ID
  Recorded    : $UTC_RECORDED ($BST_RECORDED)
  Location    : $LAT_TAG $LON_TAG

  ORIGINAL (police) : $ORIG_PATH
  PROCESSED (review): $PROC_PATH
  PUBLISH (YouTube) : $PUB_PATH
  Upload metadata   : $UPLOAD_META_PATH
  Manifest          : $MANIFEST_FILE

Upload $PUB_FILE using metadata in $UPLOAD_META_FILE (unlisted). Hand ORIGINAL + manifest to police if reported.
EOF
