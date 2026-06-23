#!/usr/bin/env bash
# Install and enable the user systemd service for glasses import inbox watching.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="$ROOT/config/import-inbox.conf"
CONF_EXAMPLE="$ROOT/config/import-inbox.conf.example"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
SERVICE="$UNIT_DIR/debike-import-watcher.service"

if [[ ! -f "$CONF" ]]; then
  cp "$CONF_EXAMPLE" "$CONF"
  echo "Created $CONF"
fi

# shellcheck source=/dev/null
source "$CONF"
IMPORT_INBOX="${IMPORT_INBOX:-/home/ajlennon/LocalSend/bike-imports}"

mkdir -p "$IMPORT_INBOX" "$IMPORT_INBOX/done" "$IMPORT_INBOX/failed" "$UNIT_DIR"
chmod +x "$ROOT/scripts/process-import-inbox.sh" "$ROOT/scripts/watch-import-inbox.sh"

cat >"$SERVICE" <<EOF
[Unit]
Description=Dangerous eBikers glasses import inbox watcher
After=default.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=DEB_IMPORT_CONF=$CONF
ExecStart=$ROOT/scripts/watch-import-inbox.sh
Restart=on-failure
RestartSec=15

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now debike-import-watcher.service

echo ""
echo "Import watcher enabled."
echo "  Inbox : $IMPORT_INBOX"
echo "  Done  : $IMPORT_INBOX/done"
echo "  Failed: $IMPORT_INBOX/failed"
echo ""
echo "Drop .MOV/.mp4 files into the inbox (LocalSend from glasses)."
echo "Ingest runs automatically; review *_PROCESSED.mp4 before YouTube upload."
echo ""
systemctl --user status debike-import-watcher.service --no-pager || true
