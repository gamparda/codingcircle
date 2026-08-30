#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${CATWAR_APP_DIR:-/opt/catwar/app}"
RELEASES_DIR="${CATWAR_RELEASES_DIR:-/opt/catwar/releases}"
STATE_DIR="${CATWAR_STATE_DIR:-/var/lib/catwar}"
SERVICE_NAME="${CATWAR_SERVICE_NAME:-catwar-server.service}"
GODOT_BIN="${CATWAR_GODOT_BIN:-/opt/godot/godot-4.7.2}"
REPOSITORY_URL="${CATWAR_REPOSITORY_URL:-https://github.com/gamparda/codingcircle.git}"
MANIFEST_URL="${CATWAR_MANIFEST_URL:-https://gamparda.github.io/codingcircle/update.json}"
LOCK_FILE="${CATWAR_UPDATE_LOCK:-/run/lock/catwar-update.lock}"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

mkdir -p "$RELEASES_DIR" "$STATE_DIR"
manifest_file=$(mktemp "$STATE_DIR/update-manifest.XXXXXX")
staging_dir=""
pending_file="$STATE_DIR/update.pending"
previous_dir="$RELEASES_DIR/previous"
swapped=0
cleanup() {
  if [[ "$swapped" -eq 1 && -d "$previous_dir" ]]; then
    systemctl stop "$SERVICE_NAME" || true
    rm -rf "$APP_DIR"
    mv "$previous_dir" "$APP_DIR"
    systemctl start "$SERVICE_NAME" || true
  fi
  rm -f "$manifest_file" "$pending_file"
  if [[ -n "$staging_dir" && -d "$staging_dir" ]]; then
    rm -rf "$staging_dir"
  fi
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
  --connect-timeout 10 --max-time 30 \
  -H 'Cache-Control: no-cache' \
  "$MANIFEST_URL" -o "$manifest_file"

target_commit=$(python3 - "$manifest_file" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8-sig") as handle:
    manifest = json.load(handle)
commit = str(manifest.get("commit", "")).lower()
if not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("update manifest contains an invalid commit")
print(commit)
PY
)
current_commit=$(git -C "$APP_DIR" rev-parse HEAD)
if [[ "$target_commit" == "$current_commit" ]]; then
  exit 0
fi

staging_dir="$RELEASES_DIR/.staging-$target_commit"
rm -rf "$staging_dir"
git clone --quiet --filter=blob:none --no-checkout "$REPOSITORY_URL" "$staging_dir"
git -C "$staging_dir" checkout --quiet --detach "$target_commit"
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --path "$staging_dir" --import >/dev/null
GODOT_SILENCE_ROOT_WARNING=1 "$GODOT_BIN" --headless --path "$staging_dir" --script res://tests/run_tests.gd

touch "$pending_file"
if [[ "$(id -u)" -eq 0 ]]; then
  chown catwar:catwar "$pending_file"
fi
ready=0
for _ in $(seq 1 600); do
  if python3 - "$STATE_DIR/server-status.json" <<'PY'
import json, os, sys, time
path = sys.argv[1]
if not os.path.exists(path) or time.time() - os.path.getmtime(path) > 5:
    raise SystemExit(1)
try:
    with open(path, encoding="utf-8") as handle:
        status = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if status.get("safe_to_update") is True and status.get("accepting_players") is False else 1)
PY
  then
    ready=1
    break
  fi
  sleep 1
done
if [[ "$ready" -ne 1 ]]; then
  echo "Cat War update postponed: server did not drain within 10 minutes" >&2
  exit 75
fi

rm -rf "$previous_dir"
systemctl stop "$SERVICE_NAME"
mv "$APP_DIR" "$previous_dir"
mv "$staging_dir" "$APP_DIR"
staging_dir=""
swapped=1
if [[ "$(id -u)" -eq 0 ]]; then
  chown -R root:root "$APP_DIR"
fi
chmod -R a-w "$APP_DIR"

if systemctl start "$SERVICE_NAME"; then
  for _ in $(seq 1 30); do
    if systemctl is-active --quiet "$SERVICE_NAME" && ss -lun | grep -q ':7777 '; then
      rm -rf "$previous_dir"
      swapped=0
      echo "CATWAR_UPDATE_APPLIED commit=$target_commit"
      exit 0
    fi
    sleep 1
  done
fi

echo "Cat War update failed readiness check; rolling back" >&2
systemctl stop "$SERVICE_NAME" || true
rm -rf "$APP_DIR"
mv "$previous_dir" "$APP_DIR"
systemctl start "$SERVICE_NAME"
swapped=0
exit 1
