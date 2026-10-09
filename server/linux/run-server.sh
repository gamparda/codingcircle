#!/usr/bin/env bash
# Starts the dedicated server from whichever layout the updater installed: a single server.pck (pack mode) or a
# project checkout (git mode). Point catwar-server.service at this file once; switching modes never touches the unit.
set -euo pipefail

APP_DIR="${CATWAR_APP_DIR:-/opt/catwar/app}"
GODOT_BIN="${CATWAR_GODOT_BIN:-/opt/godot/godot-4.7.2}"
PORT="${CATWAR_SERVER_PORT:-7777}"
[[ "$PORT" =~ ^[0-9]+$ ]] && (( PORT >= 1 && PORT <= 65535 )) || { echo "invalid CATWAR_SERVER_PORT" >&2; exit 2; }

if [[ -f "$APP_DIR/server.pck" && ! -L "$APP_DIR/server.pck" ]]; then
  exec "$GODOT_BIN" --headless --main-pack "$APP_DIR/server.pck" -- --server --port="$PORT"
fi
exec "$GODOT_BIN" --headless --path "$APP_DIR" -- --server --port="$PORT"
