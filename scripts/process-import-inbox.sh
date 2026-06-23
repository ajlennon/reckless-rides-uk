#!/usr/bin/env bash
# Process new video files in the glasses import inbox (one-shot or called by watcher).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${DEB_IMPORT_CONF:-$ROOT/config/import-inbox.conf}"
LOG="$ROOT/register/import-inbox.log"

if [[ -f "$CONF" ]]; then
  # shellcheck source=/dev/null
  source "$CONF"
fi

IMPORT_INBOX="${IMPORT_INBOX:-/home/ajlennon/LocalSend/bike-imports}"
IMPORT_NOTES="${IMPORT_NOTES:-auto-import from glasses inbox}"
AUTO_YOUTUBE_UPLOAD="${AUTO_YOUTUBE_UPLOAD:-true}"
DONE_DIR="$IMPORT_INBOX/done"
FAILED_DIR="$IMPORT_INBOX/failed"
INGEST="$ROOT/scripts/ingest-incident.sh"
UPLOAD_PENDING="$ROOT/scripts/upload-pending-incidents.sh"

mkdir -p "$IMPORT_INBOX" "$DONE_DIR" "$FAILED_DIR" "$(dirname "$LOG")"

log() {
  printf '%s %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" | tee -a "$LOG"
}

is_video() {
  local base="${1##*/}"
  base="${base,,}"
  [[ "$base" =~ \.(mov|mp4|m4v)$ ]]
}

wait_for_stable() {
  local file="$1"
  local checks="${STABLE_CHECKS:-3}"
  local interval="${STABLE_INTERVAL:-2}"
  local prev=-1 stable=0

  while [[ "$stable" -lt "$checks" ]]; do
    if [[ ! -f "$file" ]]; then
      return 1
    fi
    local size
    size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
    if [[ "$size" -gt 0 && "$size" -eq "$prev" ]]; then
      stable=$((stable + 1))
    else
      stable=0
    fi
    prev="$size"
    sleep "$interval"
  done
  return 0
}

process_file() {
  local src="$1"
  local base deb_base ingest_log
  base="$(basename "$src")"
  ingest_log="$(mktemp)"

  log "import start: $base"
  if ! wait_for_stable "$src"; then
    log "import skip (vanished): $base"
    rm -f "$ingest_log"
    return 0
  fi

  if ! "$INGEST" "$src" "$IMPORT_NOTES" 2>&1 | tee -a "$LOG" "$ingest_log"; then
    log "import failed: $base"
    rm -f "$ingest_log"
    mv -n "$src" "$FAILED_DIR/" 2>/dev/null || { cp -a "$src" "$FAILED_DIR/" && rm -f "$src"; }
    return 1
  fi

  deb_base="$(grep -m1 '^__DEB_INGEST_BASE__=' "$ingest_log" | cut -d= -f2- || true)"
  rm -f "$ingest_log"

  mv -n "$src" "$DONE_DIR/" 2>/dev/null || { cp -a "$src" "$DONE_DIR/" && rm -f "$src"; }
  log "import done: $base -> $DONE_DIR/"

  if [[ -n "$deb_base" ]]; then
    "$UPLOAD_PENDING" "$deb_base" || true
  fi
  return 0
}

shopt -s nullglob
found=0
for src in "$IMPORT_INBOX"/*; do
  [[ -f "$src" ]] || continue
  is_video "$src" || continue
  found=1
  process_file "$src" || true
done

# Upload any older incidents still missing a YouTube URL (e.g. ingested before auto-upload).
"$UPLOAD_PENDING" || true

if [[ "$found" -eq 0 ]]; then
  [[ "${DEB_IMPORT_VERBOSE:-0}" == 1 ]] && log "import inbox empty: $IMPORT_INBOX"
fi
