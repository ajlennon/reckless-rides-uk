#!/usr/bin/env bash
# Create channel playlist (if missing) and add all uploaded incidents.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=resolve-youtube-python.sh
source "$ROOT/scripts/resolve-youtube-python.sh"
exec "$(resolve_youtube_python)" "$ROOT/scripts/ensure-youtube-playlist.py" "$@"
