#!/usr/bin/env bash
# Upload incidents that have PUBLISH.mp4 + *_UPLOAD.json but no YouTube URL yet.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${RRUK_IMPORT_CONF:-${DEB_IMPORT_CONF:-$ROOT/config/import-inbox.conf}}"
LOG="$ROOT/register/import-inbox.log"

if [[ -f "$CONF" ]]; then
  # shellcheck source=/dev/null
  source "$CONF"
fi

AUTO_YOUTUBE_UPLOAD="${AUTO_YOUTUBE_UPLOAD:-true}"
AUTO_PUBLISH_MAP="${AUTO_PUBLISH_MAP:-false}"
UPLOAD="$ROOT/scripts/upload-incident.sh"
PUBLISH_MAP="$ROOT/scripts/publish-map-metadata.sh"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$LOG"
}

upload_base() {
  local base="$1"
  local upload_json="$ROOT/evidence/processed/${base}_UPLOAD.json"
  local publish_mp4="$ROOT/evidence/publish/${base}_PUBLISH.mp4"

  if [[ ! -f "$upload_json" ]]; then
    log "youtube skip (no metadata): $base"
    return 1
  fi
  if [[ ! -f "$publish_mp4" ]]; then
    log "youtube skip (no publish file): $base"
    return 1
  fi

  log "youtube upload start: $base"
  if "$UPLOAD" "$base"; then
    log "youtube upload done: $base"
    return 0
  fi
  log "youtube upload failed: $base"
  return 1
}

upload_pending() {
  local only_base="${1:-}"
  python3 - "$ROOT/evidence/processed" "$only_base" <<'PY'
import json, sys
from pathlib import Path

proc = Path(sys.argv[1])
only = sys.argv[2]
pending = []
for path in sorted(proc.glob("*_UPLOAD.json")):
    base = path.name.replace("_UPLOAD.json", "")
    if only and base != only:
        continue
    meta = json.loads(path.read_text())
    url = meta.get("youtube_url") or meta.get("youtube", {}).get("url", "")
    if not url:
        pending.append(base)
print("\n".join(pending))
PY
}

main() {
  if [[ "$AUTO_YOUTUBE_UPLOAD" != true && "$AUTO_YOUTUBE_UPLOAD" != 1 && "$AUTO_YOUTUBE_UPLOAD" != yes ]]; then
    [[ "${RRUK_IMPORT_VERBOSE:-${DEB_IMPORT_VERBOSE:-0}}" == 1 ]] && log "youtube auto-upload disabled (AUTO_YOUTUBE_UPLOAD=$AUTO_YOUTUBE_UPLOAD)"
    return 0
  fi

  local only_base="${1:-}"
  local base uploaded=0
  while IFS= read -r base; do
    [[ -n "$base" ]] || continue
    if upload_base "$base"; then
      uploaded=$((uploaded + 1))
    fi
  done < <(upload_pending "$only_base")

  [[ "$uploaded" -gt 0 ]] && log "youtube pending complete: $uploaded uploaded"

  if [[ "$uploaded" -gt 0 ]]; then
    if [[ "$AUTO_PUBLISH_MAP" =~ ^(true|1|yes)$ ]]; then
      chmod +x "$PUBLISH_MAP"
      "$PUBLISH_MAP" "Add ${uploaded} incident(s) to public map after YouTube upload." || true
    else
      log "map publish deferred — set PUBLIC in Studio, then: ./scripts/publish-map-metadata.sh"
    fi
  fi

  return 0
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "${1:-}"
fi
