#!/usr/bin/env bash
# Upload incident PUBLISH.mp4 to YouTube using *_UPLOAD.json (private by default).
# Review in Studio before public. --public requires --confirm-public-bypass.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INCIDENT="${1:?Usage: upload-incident.sh DEB-..._001 | path/to/_UPLOAD.json [--public] [--dry-run]}"

shift || true
exec python3 "$ROOT/scripts/youtube-upload.py" "$INCIDENT" "$@"
