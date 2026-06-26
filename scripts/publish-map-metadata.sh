#!/usr/bin/env bash
# Rebuild public map GeoJSON and commit/push *_UPLOAD.json after YouTube uploads.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CORE="${CORE:-$ROOT/core}"
export PYTHONPATH="${CORE}${PYTHONPATH:+:$PYTHONPATH}"
LOG="${RRUK_IMPORT_LOG:-$ROOT/register/import-inbox.log}"
GEOJSON="$ROOT/docs/data/incidents.geojson"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$LOG"
}

publish_map_metadata() {
  local msg="${1:-Update incident map metadata after YouTube upload.}"

  if ! git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    log "map publish skip (not a git repo)"
    return 1
  fi

  log "map publish start: sync YouTube privacy"
  if ! "$ROOT/scripts/sync-youtube-privacy.py" 2>&1 | tee -a "$LOG"; then
    log "map publish warning: privacy sync failed (continuing)"
  fi

  log "map publish start: rebuild geojson"
  python3 "$ROOT/scripts/build-map-data.py"

  git -C "$ROOT" add -- "$GEOJSON" "$ROOT/evidence/processed/"*_UPLOAD.json

  if git -C "$ROOT" diff --cached --quiet; then
    log "map publish skip (no metadata changes to commit)"
    return 0
  fi

  git -C "$ROOT" commit -m "$msg"

  if git -C "$ROOT" rev-parse @{u} >/dev/null 2>&1; then
    git -C "$ROOT" pull --rebase --autostash origin main
  fi

  if git -C "$ROOT" push origin main; then
    log "map publish pushed — GitHub Pages CI will deploy recklessrides.uk"
    return 0
  fi

  log "map publish push failed — commit is local; push manually"
  return 1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  publish_map_metadata "${1:-}"
fi
