#!/usr/bin/env bash
# Ingest a Meta glasses clip: archive original, blur faces, strip metadata, log for police handover.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="${CORE:-$ROOT/core}"
export PYTHONPATH="${CORE}${PYTHONPATH:+:$PYTHONPATH}"
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
import json, os, sys
from evidence_core.probe import probe_file

src = sys.argv[1]
result = probe_file(src, ffprobe=os.environ.get("FFPROBE", "ffprobe"))
print(json.dumps(result.to_legacy_meta()))
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

echo "Letterbox 16:9 + strip metadata -> publish/"
"$FFMPEG" -y -loglevel error -i "$PROC_PATH" \
  -vf "scale=-2:1080,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
  -c:v libx264 -preset medium -crf 23 \
  -c:a copy \
  -map_metadata -1 \
  "$PUB_PATH"

SHA256_PROC="$(sha256sum "$PROC_PATH" | awk '{print $1}')"
SHA256_PUB="$(sha256sum "$PUB_PATH" | awk '{print $1}')"

META_JSON="$META_JSON" NOTES="$NOTES" UPLOAD_META_PATH="$UPLOAD_META_PATH" python3 - "$MANIFEST_FILE" "$NEXT_ID" "$BASE" \
  "$UTC_RECORDED" "$BST_RECORDED" "$LAT" "$LON" "$LAT_TAG" "$LON_TAG" \
  "$ORIG_PATH" "$PROC_PATH" "$PUB_PATH" \
  "$SHA256_ORIG" "$SHA256_PROC" "$SHA256_PUB" "$INGESTED_UTC" <<'PY'
import json, os, sys
from evidence_core.manifest import rides_legacy_manifest

meta = json.loads(os.environ["META_JSON"])
(
    manifest_path, incident_id, base_name,
    utc_recorded, bst_recorded, lat, lon, lat_tag, lon_tag,
    orig_path, proc_path, pub_path,
    sha_orig, sha_proc, sha_pub, ingested_utc,
) = sys.argv[1:]

manifest = rides_legacy_manifest(
    incident_id=incident_id,
    base_name=base_name,
    recorded_utc=utc_recorded,
    recorded_bst=bst_recorded,
    latitude=lat,
    longitude=lon,
    lat_tag=lat_tag,
    lon_tag=lon_tag,
    device_model=meta.get("device", ""),
    device_comment=meta.get("device_comment", ""),
    orig_path=orig_path,
    proc_path=proc_path,
    pub_path=pub_path,
    upload_meta_path=os.environ.get("UPLOAD_META_PATH", ""),
    sha_orig=sha_orig,
    sha_proc=sha_proc,
    sha_pub=sha_pub,
    ingested_utc=ingested_utc,
    notes=os.environ.get("NOTES", ""),
)
with open(manifest_path, "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

ROOT="$ROOT" META_JSON="$META_JSON" NOTES="$NOTES" python3 - "$UPLOAD_META_PATH" "$NEXT_ID" "$BASE" \
  "$UTC_RECORDED" "$BST_RECORDED" "$LAT" "$LON" "$LAT_TAG" "$LON_TAG" \
  "$PUB_PATH" "$PROC_PATH" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

root = Path(os.environ["ROOT"])
meta = json.loads(os.environ["META_JSON"])
(
    upload_path, incident_id, base_name,
    utc_recorded, bst_recorded, lat, lon, lat_tag, lon_tag,
    pub_path, proc_path,
) = sys.argv[1:]
device = meta.get("device", "")
notes = os.environ.get("NOTES", "")
subprocess.run(
    [
        sys.executable,
        str(root / "scripts" / "upload_metadata.py"),
        "write",
        upload_path,
        incident_id,
        base_name,
        utc_recorded,
        bst_recorded,
        lat,
        lon,
        lat_tag,
        lon_tag,
        pub_path,
        proc_path,
        device,
        notes,
    ],
    check=True,
)
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

Upload $PUB_FILE as **private** using metadata in $UPLOAD_META_FILE. After manual review, set visibility to **public** in YouTube Studio. Hand ORIGINAL + manifest to police if reported.
EOF
echo "__DEB_INGEST_BASE__=$BASE"
