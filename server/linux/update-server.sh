#!/usr/bin/env bash
set -euo pipefail

APP_DIR="${CATWAR_APP_DIR:-/opt/catwar/app}"
RELEASES_DIR="${CATWAR_RELEASES_DIR:-/opt/catwar/releases}"
STATE_DIR="${CATWAR_STATE_DIR:-/var/lib/catwar}"
CONTROL_DIR="${CATWAR_CONTROL_DIR:-/var/lib/catwar-updater}"
SERVICE_NAME="${CATWAR_SERVICE_NAME:-catwar-server.service}"
SERVICE_USER="${CATWAR_SERVICE_USER:-catwar}"
SERVER_PORT="${CATWAR_SERVER_PORT:-}"
GODOT_BIN="${CATWAR_GODOT_BIN:-/opt/godot/godot-4.7.2}"
REPOSITORY_URL="${CATWAR_REPOSITORY_URL:-https://github.com/gamparda/codingcircle.git}"
MANIFEST_URL="${CATWAR_MANIFEST_URL:-https://gamparda.github.io/codingcircle/update.json}"
MANIFEST_SIGNATURE_URL="${CATWAR_MANIFEST_SIGNATURE_URL:-${MANIFEST_URL}.sig}"
PUBLIC_KEY="${CATWAR_UPDATE_PUBLIC_KEY:-/etc/catwar/update-signing-key.pem}"
LOCK_FILE="${CATWAR_UPDATE_LOCK:-${CONTROL_DIR}/update.lock}"
PYTHON_BIN="${CATWAR_PYTHON_BIN:-python3}"

fail() {
  echo "Cat War updater: $*" >&2
  return 1
}

verify_root_path() {
  local path=$1 kind=$2 required=$3 current owner mode
  if [[ -e "$path" || -L "$path" ]]; then
    [[ ! -L "$path" ]] || fail "$path must not be a symlink"
    if [[ "$kind" == directory ]]; then
      [[ -d "$path" ]] || fail "$path must be a directory"
    else
      [[ -f "$path" ]] || fail "$path must be a regular file"
    fi
    owner=$(stat -c %u -- "$path")
    mode=$(stat -c %a -- "$path")
    [[ "$owner" == 0 ]] || fail "$path must be root-owned"
    (( (8#$mode & 8#022) == 0 )) || fail "$path must not be group/other writable"
  else
    [[ "$required" == optional ]] || fail "$path must already exist"
  fi

  current=$(dirname -- "$path")
  while [[ "$current" != "/" ]]; do
    [[ -d "$current" && ! -L "$current" ]] || fail "$path has an untrusted parent"
    owner=$(stat -c %u -- "$current")
    mode=$(stat -c %a -- "$current")
    [[ "$owner" == 0 ]] || fail "$path parent must be root-owned"
    (( (8#$mode & 8#022) == 0 )) || fail "$path parent must not be group/other writable"
    current=$(dirname -- "$current")
  done
}

validate_root_paths() {
  verify_root_path "$APP_DIR" directory required
  verify_root_path "$RELEASES_DIR" directory optional
  verify_root_path "$CONTROL_DIR" directory required
  verify_root_path "$LOCK_FILE" file optional
}

valid_commit() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]]
}

verify_key_file() {
  local key=$1 expected_uid=$2 owner mode parent
  [[ -f "$key" && ! -L "$key" ]] || fail "signing key must be a regular, non-symlink file"
  owner=$(stat -c %u -- "$key")
  mode=$(stat -c %a -- "$key")
  [[ "$owner" == "$expected_uid" ]] || fail "signing key has an untrusted owner"
  (( (8#$mode & 8#022) == 0 )) || fail "signing key is group/other writable"

  # Production keys must also be reached only through root-controlled directories.
  if [[ "$expected_uid" == 0 ]]; then
    parent=$(dirname -- "$key")
    while [[ "$parent" != "/" ]]; do
      [[ ! -L "$parent" && -d "$parent" ]] || fail "signing key parent is not a trusted directory"
      owner=$(stat -c %u -- "$parent")
      mode=$(stat -c %a -- "$parent")
      [[ "$owner" == 0 ]] || fail "signing key parent is not root-owned"
      (( (8#$mode & 8#022) == 0 )) || fail "signing key parent is group/other writable"
      parent=$(dirname -- "$parent")
    done
  fi
}

read_manifest_commit() {
  local manifest=$1
  [[ -f "$manifest" && ! -L "$manifest" ]] || fail "manifest must be a regular file"
  "$PYTHON_BIN" - "$manifest" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8-sig") as handle:
    manifest = json.load(handle)
commit = str(manifest.get("commit", "")).lower()
if not re.fullmatch(r"[0-9a-f]{40}", commit):
    raise SystemExit("update manifest contains an invalid commit")
print(commit)
PY
}

verify_manifest() {
  local manifest=$1 signature=$2 key=$3 expected_uid=${4:-0} raw_signature
  verify_key_file "$key" "$expected_uid"
  [[ -f "$manifest" && ! -L "$manifest" && -f "$signature" && ! -L "$signature" ]] || \
    fail "manifest and signature must be regular files"
  raw_signature="${signature}.raw.$$"
  rm -f -- "$raw_signature"
  if ! openssl base64 -d -A -in "$signature" -out "$raw_signature"; then
    rm -f -- "$raw_signature"
    fail "manifest signature is not valid base64"
    return 1
  fi
  if ! openssl dgst -sha256 -verify "$key" -signature "$raw_signature" "$manifest" >/dev/null; then
    rm -f -- "$raw_signature"
    fail "manifest signature verification failed"
    return 1
  fi
  rm -f -- "$raw_signature"
  read_manifest_commit "$manifest"
}

validate_update_graph() {
  local repo=$1 current=$2 target=$3 trusted=${4:-}
  valid_commit "$current" || fail "current commit is invalid"
  valid_commit "$target" || fail "target commit is invalid"
  [[ -z "$trusted" ]] || valid_commit "$trusted" || fail "trusted commit is invalid"
  git -C "$repo" cat-file -e "${current}^{commit}" 2>/dev/null || fail "current commit is unavailable"
  git -C "$repo" cat-file -e "${target}^{commit}" 2>/dev/null || fail "target commit is unavailable"
  git -C "$repo" show-ref --verify --quiet refs/remotes/origin/main || fail "origin/main is unavailable"
  git -C "$repo" merge-base --is-ancestor "$current" "$target" || fail "downgrade or divergent update rejected"
  git -C "$repo" merge-base --is-ancestor "$target" refs/remotes/origin/main || fail "target is not on origin/main"
  if [[ -n "$trusted" ]]; then
    git -C "$repo" cat-file -e "${trusted}^{commit}" 2>/dev/null || fail "last trusted commit is unavailable"
    git -C "$repo" merge-base --is-ancestor "$trusted" "$target" || fail "manifest replay rejected"
  fi
}

check_readiness() {
  local service=$1 port=$2 main_pid sockets socket
  [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 )) || fail "server port is invalid"
  systemctl is-active --quiet "$service" || return 1
  main_pid=$(systemctl show --property MainPID --value "$service")
  [[ "$main_pid" =~ ^[0-9]+$ ]] && (( main_pid > 1 )) || return 1
  sockets=$(ss -H -lunp "sport = :$port") || return 1
  while IFS= read -r socket; do
    if grep -Eq ":${port}[[:space:]]" <<<"$socket" && grep -Eq "pid=${main_pid}," <<<"$socket"; then
      return 0
    fi
  done <<<"$sockets"
  return 1
}

case "${1:-}" in
  --verify-manifest)
    [[ $# -eq 5 ]] || fail "usage: --verify-manifest MANIFEST SIGNATURE KEY TRUSTED_UID"
    verify_manifest "$2" "$3" "$4" "$5"
    exit
    ;;
  --validate-update-graph)
    [[ $# -ge 4 && $# -le 5 ]] || fail "usage: --validate-update-graph REPO CURRENT TARGET [TRUSTED]"
    validate_update_graph "$2" "$3" "$4" "${5:-}"
    exit
    ;;
  --check-readiness)
    [[ $# -eq 3 ]] || fail "usage: --check-readiness SERVICE PORT"
    check_readiness "$2" "$3"
    exit
    ;;
esac

[[ "$(id -u)" -eq 0 ]] || fail "the production updater must run as root"
[[ -n "$SERVER_PORT" ]] || fail "CATWAR_SERVER_PORT must be configured"
[[ -d "$STATE_DIR" ]] || fail "service state directory must exist"
[[ ! -L "$STATE_DIR" ]] || fail "service state directory must not be a symlink"
state_owner=$(stat -c %U -- "$STATE_DIR")
[[ "$state_owner" == "$SERVICE_USER" ]] || fail "service state directory must be owned by $SERVICE_USER"

validate_root_paths
install -d -o root -g root -m 0700 -- "$CONTROL_DIR"
[[ -d "$CONTROL_DIR" && ! -L "$CONTROL_DIR" ]] || fail "control directory must not be a symlink"
[[ "$(stat -c %u -- "$CONTROL_DIR")" == 0 ]] || fail "control directory must be root-owned"
(( (8#$(stat -c %a -- "$CONTROL_DIR") & 8#077) == 0 )) || fail "control directory permissions are too broad"
install -d -o root -g root -m 0755 -- "$RELEASES_DIR"

exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

manifest_file=$(mktemp "$CONTROL_DIR/update-manifest.XXXXXX")
staging_dir=""
test_dir=""
pending_file="$STATE_DIR/update.pending"
previous_dir="$RELEASES_DIR/previous"
trusted_commit_file="$CONTROL_DIR/trusted-commit"
swapped=0

run_as_service_user() {
  runuser --user "$SERVICE_USER" -- "$@"
}

clear_pending() {
  run_as_service_user /usr/bin/rm -f -- "$pending_file" || true
}

rollback() {
  systemctl stop "$SERVICE_NAME" || true
  rm -rf -- "$APP_DIR"
  mv -- "$previous_dir" "$APP_DIR"
  systemctl start "$SERVICE_NAME" || true
  swapped=0
}

cleanup() {
  if [[ "$swapped" -eq 1 && -d "$previous_dir" ]]; then
    rollback
  fi
  clear_pending
  rm -f -- "$manifest_file"
  [[ -z "$staging_dir" ]] || rm -rf -- "$staging_dir"
  [[ -z "$test_dir" ]] || rm -rf -- "$test_dir"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
  --connect-timeout 10 --max-time 30 -H 'Cache-Control: no-cache' \
  "$MANIFEST_URL" -o "$manifest_file"
target_commit=$(read_manifest_commit "$manifest_file")

current_commit=$(git -C "$APP_DIR" rev-parse HEAD)
current_commit=${current_commit,,}
valid_commit "$current_commit" || fail "installed application commit is invalid"
trusted_commit=""
if [[ -e "$trusted_commit_file" ]]; then
  [[ -f "$trusted_commit_file" && ! -L "$trusted_commit_file" ]] || fail "trusted commit state is invalid"
  read -r trusted_commit < "$trusted_commit_file"
  valid_commit "$trusted_commit" || fail "trusted commit state is corrupt"
fi
if [[ "$target_commit" == "$current_commit" ]]; then
  [[ -z "$trusted_commit" || "$trusted_commit" == "$current_commit" ]] || fail "installed commit predates trusted state"
  exit 0
fi

# Execute all checkout-controlled import and test code only as the service account.
test_dir="$RELEASES_DIR/.testing-$target_commit"
rm -rf -- "$test_dir"
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0700 -- "$test_dir"
run_as_service_user git clone --quiet --filter=blob:none --no-checkout "$REPOSITORY_URL" "$test_dir"
run_as_service_user git -C "$test_dir" fetch --quiet origin main
run_as_service_user git -C "$test_dir" checkout --quiet --detach "$target_commit"
validate_update_graph "$test_dir" "$current_commit" "$target_commit" "$trusted_commit"
run_as_service_user "$GODOT_BIN" --headless --path "$test_dir" --import >/dev/null
run_as_service_user "$GODOT_BIN" --headless --path "$test_dir" --script res://tests/run_tests.gd
rm -rf -- "$test_dir"
test_dir=""

# Build a fresh root-owned deployment tree; no files produced by tests are promoted.
staging_dir="$RELEASES_DIR/.staging-$target_commit"
rm -rf -- "$staging_dir"
git clone --quiet --filter=blob:none --no-checkout "$REPOSITORY_URL" "$staging_dir"
git -C "$staging_dir" fetch --quiet origin main
validate_update_graph "$staging_dir" "$current_commit" "$target_commit" "$trusted_commit"
git -C "$staging_dir" -c core.hooksPath=/dev/null checkout --quiet --detach "$target_commit"
[[ "$(git -C "$staging_dir" rev-parse HEAD)" == "$target_commit" ]] || fail "staged checkout changed unexpectedly"
chown -hR root:root -- "$staging_dir"
chmod -R a-w -- "$staging_dir"

# The writable state directory is never accessed as root: a malicious symlink can
# at worst exercise the already-unprivileged catwar account.
run_as_service_user /usr/bin/touch -- "$pending_file"
ready=0
service_uid=$(id -u "$SERVICE_USER")
for _ in $(seq 1 600); do
  if "$PYTHON_BIN" - "$STATE_DIR/server-status.json" "$service_uid" <<'PY'
import json, os, stat, sys, time
path, expected_uid = sys.argv[1], int(sys.argv[2])
try:
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    info = os.fstat(fd)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != expected_uid or time.time() - info.st_mtime > 5:
        raise OSError("untrusted status file")
    with os.fdopen(fd, encoding="utf-8") as handle:
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

rm -rf -- "$previous_dir"
systemctl stop "$SERVICE_NAME"
mv -- "$APP_DIR" "$previous_dir"
mv -- "$staging_dir" "$APP_DIR"
staging_dir=""
swapped=1

if systemctl start "$SERVICE_NAME"; then
  for _ in $(seq 1 30); do
    if check_readiness "$SERVICE_NAME" "$SERVER_PORT"; then
      trusted_temp=$(mktemp "$CONTROL_DIR/trusted-commit.XXXXXX")
      printf '%s\n' "$target_commit" > "$trusted_temp"
      chmod 0600 "$trusted_temp"
      mv -f -- "$trusted_temp" "$trusted_commit_file"
      rm -rf -- "$previous_dir"
      swapped=0
      echo "CATWAR_UPDATE_APPLIED commit=$target_commit"
      exit 0
    fi
    sleep 1
  done
fi

echo "Cat War update failed readiness check; rolling back" >&2
rollback
exit 1
