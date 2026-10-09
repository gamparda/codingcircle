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
LOCK_FILE="${CATWAR_UPDATE_LOCK:-${CONTROL_DIR}/update.lock}"
PYTHON_BIN="${CATWAR_PYTHON_BIN:-python3}"
# "git" (default) builds every release from a fresh checkout and imports its assets. "pack" installs the single
# CI-built game-data pack instead: no clone, no import, no test run on this machine.
UPDATE_MODE="${CATWAR_UPDATE_MODE:-git}"
HISTORY_DIR="${CATWAR_HISTORY_DIR:-${CONTROL_DIR}/history.git}"
PACK_URL="${CATWAR_PACK_URL:-${MANIFEST_URL%/*}/CatWarDesktop.pck}"
PACK_MAX_BYTES="${CATWAR_PACK_MAX_BYTES:-300000000}"

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

# Prints "commit pack_version pack_commit pack_sha256 pack_url" for a manifest that publishes a desktop pack.
read_pack_manifest() {
  local manifest=$1
  [[ -f "$manifest" && ! -L "$manifest" ]] || fail "manifest must be a regular file"
  "$PYTHON_BIN" - "$manifest" <<'PY'
import json, re, sys
with open(sys.argv[1], encoding="utf-8-sig") as handle:
    manifest = json.load(handle)
def need(name, pattern):
    value = str(manifest.get(name, ""))
    if not re.fullmatch(pattern, value):
        raise SystemExit("update manifest has no valid " + name)
    return value
commit = need("commit", r"[0-9a-f]{40}").lower()
version = need("desktop_pack_version", r"[0-9]+\.[0-9]+\.[0-9]+")
pack_commit = need("desktop_pack_commit", r"[0-9a-fA-F]{40}").lower()
digest = need("desktop_pack_sha256", r"[0-9a-fA-F]{64}").lower()
url = str(manifest.get("desktop_pack_url", ""))
if re.search(r"[\s'\"\\]", url):
    raise SystemExit("update manifest pack url is not plain")
if pack_commit != commit:
    raise SystemExit("update manifest pack commit differs from its commit")
print(commit, version, pack_commit, digest, url)
PY
}

# A root-owned, commits-only mirror of origin/main. Only ancestry questions are asked of it, and it never executes
# anything from the repository, so the first run downloads a little history and later runs only the new commits.
refresh_history() {
  [[ -d "$HISTORY_DIR/objects" ]] || {
    rm -rf -- "$HISTORY_DIR"
    git init --quiet --bare "$HISTORY_DIR"
    git -C "$HISTORY_DIR" remote add origin "$REPOSITORY_URL"
    git -C "$HISTORY_DIR" config remote.origin.promisor true
    git -C "$HISTORY_DIR" config remote.origin.partialclonefilter tree:0
  }
  GIT_TERMINAL_PROMPT=0 git -C "$HISTORY_DIR" fetch --quiet --no-tags origin '+refs/heads/main:refs/remotes/origin/main'
}

installed_commit() {
  local value
  if [[ -f "$APP_DIR/server.pck" && ! -L "$APP_DIR/server.pck" ]]; then
    [[ -f "$APP_DIR/commit" && ! -L "$APP_DIR/commit" ]] || fail "installed pack has no commit record"
    read -r value < "$APP_DIR/commit"
  else
    value=$(git -C "$APP_DIR" rev-parse HEAD)
  fi
  value=${value,,}
  valid_commit "$value" || fail "installed application commit is invalid"
  printf '%s\n' "$value"
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
  --validate-update-graph)
    [[ $# -ge 4 && $# -le 5 ]] || fail "usage: --validate-update-graph REPO CURRENT TARGET [TRUSTED]"
    validate_update_graph "$2" "$3" "$4" "${5:-}"
    exit
    ;;
  --read-pack-manifest)
    [[ $# -eq 2 ]] || fail "usage: --read-pack-manifest MANIFEST"
    read_pack_manifest "$2"
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
  rm -f -- "$manifest_file" "$CONTROL_DIR/pack-${target_commit:-none}.pck"
  [[ -z "$staging_dir" ]] || rm -rf -- "$staging_dir"
  [[ -z "$test_dir" ]] || rm -rf -- "$test_dir"
}
trap cleanup EXIT

curl --fail --silent --show-error --location \
  --connect-timeout 10 --max-time 30 -H 'Cache-Control: no-cache' \
  "$MANIFEST_URL" -o "$manifest_file"
target_commit=$(read_manifest_commit "$manifest_file")

current_commit=$(installed_commit)
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

build_pack_staging() {
  local fields pack_version pack_commit pack_sha pack_url download actual size
  fields=$(read_pack_manifest "$manifest_file")
  read -r _ pack_version pack_commit pack_sha pack_url <<<"$fields"
  [[ "$pack_commit" == "$target_commit" ]] || fail "pack was not built from the manifest commit"
  [[ "$pack_url" == "$PACK_URL" ]] || fail "pack url is not the official one"

  refresh_history
  validate_update_graph "$HISTORY_DIR" "$current_commit" "$target_commit" "$trusted_commit"

  test_dir="$RELEASES_DIR/.testing-$target_commit"
  rm -rf -- "$test_dir"
  install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0700 -- "$test_dir"
  download="$CONTROL_DIR/pack-$target_commit.pck"
  rm -f -- "$download"
  curl --fail --silent --show-error --location --proto '=https' --max-redirs 3 \
    --connect-timeout 10 --max-time 600 --max-filesize "$PACK_MAX_BYTES" \
    -H 'Cache-Control: no-cache' "$pack_url" -o "$download"
  [[ -f "$download" && ! -L "$download" ]] || fail "pack download is not a regular file"
  actual=$(sha256sum -- "$download")
  actual=${actual%% *}
  [[ "$actual" == "$pack_sha" ]] || fail "pack SHA-256 does not match the manifest"
  size=$(stat -c %s -- "$download")
  (( size > 0 && size <= PACK_MAX_BYTES )) || fail "pack size is out of range"

  # The unprivileged service account opens a private copy: it must start, carry the manifest commit and load the
  # server code. Nothing it writes is ever promoted.
  install -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0600 -- "$download" "$test_dir/server.pck"
  run_as_service_user "$GODOT_BIN" --headless --main-pack "$test_dir/server.pck" --script res://tests/pack_selfcheck.gd -- "$target_commit"
  rm -rf -- "$test_dir"
  test_dir=""

  staging_dir="$RELEASES_DIR/.staging-$target_commit"
  rm -rf -- "$staging_dir"
  install -d -o root -g root -m 0755 -- "$staging_dir"
  install -o root -g root -m 0644 -- "$download" "$staging_dir/server.pck"
  printf '%s\n' "$target_commit" > "$staging_dir/commit"
  chown root:root -- "$staging_dir/commit"
  chmod 0644 -- "$staging_dir/commit"
  rm -f -- "$download"
}

build_git_staging() {
# Execute all checkout-controlled import and test code only as the service account.
test_dir="$RELEASES_DIR/.testing-$target_commit"
rm -rf -- "$test_dir"
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0700 -- "$test_dir"
run_as_service_user git clone --quiet --filter=blob:none --no-checkout "$REPOSITORY_URL" "$test_dir"
run_as_service_user git -C "$test_dir" fetch --quiet origin main
run_as_service_user git -C "$test_dir" checkout --quiet --detach "$target_commit"
run_as_service_user "$0" --validate-update-graph "$test_dir" "$current_commit" "$target_commit" "$trusted_commit"
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
chmod -R a-w,a+rX -- "$staging_dir"
[[ ! -e "$staging_dir/.godot" && ! -L "$staging_dir/.godot" ]] || fail "staged checkout controls .godot path"
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0700 -- "$staging_dir/.godot"
run_as_service_user "$GODOT_BIN" --headless --path "$staging_dir" --import >/dev/null
chown -hR root:root -- "$staging_dir"
chmod -R a-w,a+rX -- "$staging_dir"

}

if [[ "$UPDATE_MODE" == pack ]]; then
  build_pack_staging
else
  build_git_staging
fi

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
