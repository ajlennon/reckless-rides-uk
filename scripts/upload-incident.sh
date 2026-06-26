#!/usr/bin/env bash
# Upload incident PUBLISH.mp4 to YouTube using *_UPLOAD.json (private by default).
# Review in Studio before public. --public requires --confirm-public-bypass.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INCIDENT="${1:?Usage: upload-incident.sh DEB-..._001 | path/to/_UPLOAD.json [--public] [--dry-run]}"

# shellcheck source=resolve-youtube-python.sh
source "$ROOT/scripts/resolve-youtube-python.sh"
YOUTUBE_PY="$(resolve_youtube_python)"

shift || true
exec "$YOUTUBE_PY" "$ROOT/scripts/youtube-upload.py" "$INCIDENT" "$@"
