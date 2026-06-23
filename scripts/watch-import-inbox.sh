#!/usr/bin/env bash
# Poll the glasses import inbox and run ingest-incident.sh on new videos.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${DEB_IMPORT_CONF:-$ROOT/config/import-inbox.conf}"

if [[ -f "$CONF" ]]; then
  # shellcheck source=/dev/null
  source "$CONF"
fi

POLL_SECONDS="${POLL_SECONDS:-10}"
IMPORT_INBOX="${IMPORT_INBOX:-/home/ajlennon/LocalSend/bike-imports}"

mkdir -p "$IMPORT_INBOX" "$IMPORT_INBOX/done" "$IMPORT_INBOX/failed"

echo "Dangerous eBikers import watcher"
echo "  inbox : $IMPORT_INBOX"
echo "  poll  : ${POLL_SECONDS}s"
echo "  log   : $ROOT/register/import-inbox.log"
echo "Press Ctrl+C to stop."

while true; do
  "$ROOT/scripts/process-import-inbox.sh" || true
  sleep "$POLL_SECONDS"
done
