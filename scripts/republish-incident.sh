#!/usr/bin/env bash
# Rebuild *_PUBLISH.mp4 (16:9 letterbox) and *_UPLOAD.json from existing processed file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASE="${1:?Usage: republish-incident.sh DEB-20260623T080303Z_53.4092N_2.9778W_001}"

PROC="$ROOT/evidence/processed/${BASE}_PROCESSED.mp4"
PUB="$ROOT/evidence/publish/${BASE}_PUBLISH.mp4"
FFMPEG="${FFMPEG:-ffmpeg}"

[[ -f "$PROC" ]] || { echo "Missing: $PROC" >&2; exit 1; }

echo "Letterbox 16:9 -> $PUB"
"$FFMPEG" -y -loglevel error -i "$PROC" \
  -vf "scale=-2:1080,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:black" \
  -c:v libx264 -preset medium -crf 23 \
  -c:a copy \
  -map_metadata -1 \
  "$PUB"

"$ROOT/scripts/regenerate-upload-metadata.sh" "$BASE"
echo "Done. Re-upload $PUB (delete Short on YouTube first if replacing)."
