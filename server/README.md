# Cat War server

The dedicated server uses the same authoritative Godot code and executable as the client.

Run from PowerShell after exporting the project:

```powershell
.\builds\CatWar.exe --headless -- --server --port=7777
```

On an installed copy, launch **Cat War Dedicated Server** from the Start menu or run `StartServer.cmd`. The server listens on UDP. Open the selected UDP port in the host firewall and cloud security group/router as required.

## Persistence and storage failures

Statistics and leaderboard files are checked field by field on startup. Valid entries remain
available when neighboring entries have invalid types, counts, participant IDs, dates or times;
invalid entries are excluded from queries and subsequent submissions. Loading alone does not
rewrite the original file. Daily and weekly boards retain the highest score and, for equal
scores, the shortest completion time, matching the client's local records and offline queue.

Opt-in solo reports carry the anonymous install ID and an increasing sequence. The server
stores only the highest sequence per install alongside the aggregate counters in the same
atomic file replacement. It acknowledges a report only after that write succeeds, so a lost
acknowledgement, reconnect, or stale client queue after restart does not count the result twice.
Challenge scores are also acknowledged only after their board file is saved. The client keeps
unconfirmed queues on disk and retries every five seconds while connected; confirmed reports
advance the next queued result after half a second. Existing request limits still apply. Each
connection may submit 40 new reports per 60-second window; its quota renews without requiring
a reconnect. Already counted reports can retry persistence acknowledgements even at capacity
and do not consume the quota. No nickname, IP, or individual deck history is stored in receipts.
Receipts are limited to 100,000 installs per ruleset. At capacity, new identities remain
unconfirmed instead of evicting existing receipts and risking duplicate counts; online aggregate
statistics, existing reporters, and challenge boards continue to work.

The statistics ruleset comes from `build_info.json`'s `version` (the content version generated
from `release.json`). Solo reports persist their originating version, and both report RPCs reject
versions other than the server's active ruleset. Clients also reject foreign-ruleset snapshots.
Old reports without a version remain marked `0`, excluded from current submissions while
retained within the existing 20-result queue. Historical `stats_0.json` files remain untouched;
they are not merged into a versioned store because their original rulesets cannot be recovered.
Challenge score dates and their existing submission policy are unchanged.

Daily and weekly leaderboards also use the active content ruleset and are persisted in
`daily_board_<ruleset>.json`. Score submissions, board requests, responses and persistence
receipts carry the version; mismatched versions are rejected. The legacy `daily_board.json`
is left untouched because its originating rules cannot be inferred. New versions start fresh
boards, including when a release occurs during the same UTC day or week. Client profiles retain
previous-version best scores within their existing day/week history limits, while comparing
only scores from the same version. Lifetime clears and daily streaks survive rules updates.
Old or unversioned queued scores are not submitted; they expire under the existing date policy
or are replaced by a new-version score for the same board. A delayed old-version receipt cannot
clear that replacement. Client and server must be deployed from the same build as usual.
Restored client queues use the same score/time validation as new submissions; malformed
or out-of-range queued scores are excluded instead of retrying forever or fabricating a
zero-second time. Invalid entries do not consume the four-valid-score queue limit.

The server stores shared replay codes, aggregate statistics, and the challenge leaderboard in
`CATWAR_STATE_DIR`, or `user://server_state` when that environment variable is unset. Finished
match archives remain in `user://replays`. An upload receives a code only after the shared file
has been written successfully; a failed upload can be retried from the client's **코드** button
or shared directly with **복사**.

Failed match archive and public shelf writes keep the completed recording in memory. Each
destination retries independently every 30 seconds, without counting the match or saving a
successful destination twice. Statistics and leaderboard writes also retry when the server is
idle. Logs mark `REPLAY_SAVE_PENDING` and `REPLAY_SAVE_RECOVERED`; `server-status.json` reports
`pending_saves`, and automatic updates wait until these writes succeed. Stop or crash recovery
cannot retain data that could not be written anywhere: repair disk space or permissions before
manually restarting a server with pending writes. Replays exceeding the share size limit still
receive a local archive and log `REPLAY_SHARE_SKIPPED` rather than retrying indefinitely.

Shared replay files are validated again on startup, and summaries are rebuilt from their replay
contents. The shelf keeps the newest 200 entries and preserves creation order across restarts.
A failed oldest-file deletion is logged as `REPLAY_SHELF_TRIM_PENDING` and retried periodically;
further uploads are refused while the shelf remains over its limit.

Share-code reuse is based on validated, parsed JSON content with sorted keys and full numeric
precision. Saving and reloading a replay, JSON whitespace, key order, and compression do not
create another code for the same content. Notes, clips, and metadata remain part of that content.
Existing files and codes are preserved; when legacy files encode equivalent content, new uploads
reuse the oldest retained code. If that file is pruned, the next retained equivalent code is reused.
Public flags are kept per existing code, and promotion still requires a successful disk write.

If completed replays awaiting persistence reach 16 recordings or 100,000 commands, the
server pauses new battles (quick matches, room starts and rematches) with a retryable storage
message. Existing battles, reconnects and spectators continue. Waiting quick-match
players keep their queue position and pairing resumes after the periodic writes recover.
This prevents an ongoing outage from accepting more battles once the backlog reaches its
threshold; already active battles may still finish and add pending records. It is not a hard
memory limit. `REPLAY_BACKLOG` logs pause/recovery transitions; `server-status.json` exposes
`accepting_matches`, `replay_backlog_full` and `pending_replay_commands` separately from the
update-related `accepting_players` flag. Update draining still takes priority after recovery.

Local match archives keep the newest 50 readable files. Unreadable originals are preserved
for manual recovery or deletion and do not consume those slots. Archive cleanup failures log
`REPLAY_TRIM_PENDING` and retry every 30 seconds as well as after the next archive save.
New archives persist a local sequence inside the replay, so clock reversals, filename changes
and process restarts do not change their retention order. Note rewrites preserve that sequence;
shared text omits it and local imports receive a new sequence. Legacy files without a valid
sequence keep their filename order behind new archives. Their historical save order cannot
be recovered reliably. Copying a raw sequenced JSON between archives also copies its sequence;
use share text when the destination should assign a fresh local order.
The server's in-memory diagnostic path history also retains only the latest 50 successful
archive paths. This history does not control pending writes or delete files.

`server-status.json` includes `reported_result_capacity` with `ruleset`, `used`, `limit` and
`new_installations_paused`. At the 100,000-install receipt limit, only new installations' anonymous
result confirmations are withheld; existing installations, online results and challenge scores
continue. `STATS_REPORT_CAPACITY` logs entry into or exit from this state, including a full store
loaded at startup. Receipt capacity is separate from `pending_saves` and match admission. Repairing
disk permissions will not free receipt slots. Keep the current ruleset's receipts: deleting them
can count queued retries again. Each new content ruleset has its own receipt store and capacity;
keep older files for audit rather than clearing them or changing rules solely to free slots.

## Encrypted connections (DTLS)

Every ENet connection is DTLS-encrypted; unencrypted clients cannot connect. Official clients
connect to `ruellyya.kr`, `211.176.222.145` or `192.168.0.4` and verify the server certificate as
`ruellyya.kr` against the public CA list, so a production server needs a CA-signed certificate
for that name (Let's Encrypt works). Point the server at the PEM files, for example in
`/etc/catwar/server.env` (read by the server service as an `EnvironmentFile`):

```
CATWAR_TLS_CERT=/etc/catwar/tls/fullchain.pem
CATWAR_TLS_KEY=/etc/catwar/tls/privkey.pem
```

The `catwar` service account must be able to read both files. Let's Encrypt keeps its keys
root-only, so copy them with a certbot deploy hook (`/etc/letsencrypt/renewal-hooks/deploy/catwar`):

```sh
#!/bin/sh
install -o catwar -g catwar -m 600 "$RENEWED_LINEAGE/privkey.pem" /etc/catwar/tls/privkey.pem
install -o catwar -g catwar -m 644 "$RENEWED_LINEAGE/fullchain.pem" /etc/catwar/tls/fullchain.pem
```

The server reads the certificate at start. Renewals happen 30 days before expiry, so the next
restart (any update does one) picks up the new files; restart manually in a quiet moment if no
update ships in that window. If the variables are set but either file cannot be read, the server
refuses to start (`TLS_CONFIG_INVALID`) rather than fall back. Without the variables it uses the
public development identity in `scripts/net/TransportSecurity.gd` and logs
`TLS_CERTIFICATE development`: local and test clients still connect encrypted, official clients
refuse it.

## Accounts (Google sign-in)

Accounts are required to play on Android (the PC version plays without one) and live in `<state dir>/accounts.json` (written atomically,
retried with the other stores). The file holds a random per-server salt, a salted SHA-256 of each
account's Google subject, the nickname, creation and last-login times, and SHA-256 hashes of up to
five 30-day session tokens. It never holds e-mail addresses, raw Google IDs or raw session tokens.
Back it up with the rest of the state directory and keep it readable only by `catwar`.

Clients send a Google ID token only over a verified connection. The server checks it against
Google's signing keys, which it downloads from `https://www.googleapis.com/oauth2/v3/certs` at
start, hourly, and when a token names an unknown key (at most once a minute), so the server needs
outbound HTTPS to `www.googleapis.com`. Logs: `ACCOUNT_CREATED`, `ACCOUNT_DELETED`,
`ACCOUNT_KEYS_FETCH_FAILED`. Tokens must be issued for the web OAuth client in
`scripts/accounts/GoogleIdToken.gd`; `CATWAR_GOOGLE_CLIENT_IDS` (comma-separated) replaces that
list, for example to accept a future desktop client as well.

### Ranked games, reports and cloud saves

- **Ranked ratings** are kept in each account record (`rating`, `ranked` win/loss/draw counts) in
  `accounts.json`. Logs: `RANKED_MATCH`, `RANKED_RESULT`.
- **Cloud saves** live in `<state dir>/saves/<first two id characters>/<account id>.json`, one file per account
  (the player's portable progress, at most 512 KB, with a revision number). Deleting an account deletes its save.
- **Reports** are appended to `<state dir>/reports.jsonl`, one JSON object per line: time, reporter account,
  reported account and nickname, match (`room-code-match-id`) and reason (`nickname`, `manner`, `cheat`).
  Each account can report each match once and ten times a day. Log: `PLAYER_REPORT`. Review the file by hand;
  nothing is acted on automatically. Reports older than a year are deleted daily (`REPORTS_PRUNED`), as the
  privacy policy states.

### Backups and damaged files

At start and then once a day the server copies the player data in the state directory (every top-level
`*.json`/`*.jsonl` file and the `saves/` folder; not replay archives) to `<state dir>/backups/<YYYY-MM-DD>/`
and keeps the last 14 days. Logs: `BACKUP_DONE`, `BACKUP_FAILED`. If `accounts.json` cannot be read at start,
the server renames it to `accounts.json.corrupt-<unix time>` and restores the newest readable backup
(`STORE_CORRUPT`, `STORE_RESTORED`; `STORE_NOT_RESTORED` means no backup could be read and the server starts
with no accounts — stop it and restore by hand). Copy `backups/` off the machine as well; a disk failure takes
both.

## Production Linux server

The official Linux service runs Godot headlessly under `catwar-server.service`. Install
`server/linux/catwar-update.service` and `server/linux/catwar-update.timer` to poll the
GitHub Pages update manifest every two minutes. An update is staged and tested
first. The live server then stops accepting new players, waits for active matches to
finish, swaps the application tree, and restarts. A failed readiness check rolls back to
the previous tree.

### Pack mode (no clone, no import, no tests on the server)

By default every update clones the repository twice, imports the assets twice and runs the unit tests on the server.
In **pack mode** the updater instead downloads the one game-data pack that CI built and tested
(`CatWarDesktop.pck`, about 6 MB), checks its SHA-256 against the manifest, runs a short self-check as the `catwar`
account (`tests/pack_selfcheck.gd`: starts, carries the manifest commit, loads the server code) and swaps it in. The
safety rules stay: the target must be a forward descendant of the installed/last trusted commit and an ancestor of
`origin/main`. That is answered by a root-owned, commits-only mirror (`$CONTROL_DIR/history.git`) that downloads only new
commits on each run and never executes anything from the repository.

One-time switch (the agent that manages the server does this):

1. Install `server/linux/run-server.sh` next to the updater (root-owned, mode 0755):
   `install -o root -g root -m 0755 server/linux/run-server.sh /usr/local/libexec/catwar/run-server.sh`
2. Point `catwar-server.service` at it: `ExecStart=/usr/local/libexec/catwar/run-server.sh`. It reads
   `CATWAR_APP_DIR`, `CATWAR_GODOT_BIN` and `CATWAR_SERVER_PORT` from `/etc/catwar/server.env` and starts either layout
   (`server.pck` or a project checkout), so rollbacks and mode changes never need the unit edited again. Run
   `systemctl daemon-reload`, and restart the server once.
3. Install the new `update-server.sh` and add `CATWAR_UPDATE_MODE=pack` to `/etc/catwar/server.env`.
4. Run the updater once (`systemctl start catwar-update.service`). The first run converts the checkout into
   `server.pck` + `commit`; later runs only swap the pack. Without `CATWAR_UPDATE_MODE=pack` nothing changes.

### Secure updater installation

The updater is a root oneshot because only it may replace the root-owned application
tree and control the game service. Do **not** execute the copy inside the application
tree: a deployed checkout is replaceable. Install an independently reviewed copy as root:

```sh
install -d -o root -g root -m 0755 /usr/local/libexec/catwar
install -o root -g root -m 0755 server/linux/update-server.sh \
  /usr/local/libexec/catwar/update-server.sh
install -d -o catwar -g catwar -m 0750 /var/lib/catwar
install -d -o root -g root -m 0700 /var/lib/catwar-updater
```

Create root-owned `/etc/catwar/server.env` (not writable by `catwar`) with the actual UDP
port and any site-specific paths. The port is mandatory and deliberately has no updater
default:

```sh
CATWAR_SERVER_PORT=8123
CATWAR_STATE_DIR=/var/lib/catwar
CATWAR_CONTROL_DIR=/var/lib/catwar-updater
```

The service account owns only `CATWAR_STATE_DIR`; manifest files, the last trusted commit,
and other updater control state stay in the separate root-only control directory. Drain
markers and project import/tests run as `catwar`, never root. A candidate must be a forward
descendant of the installed/last trusted commit and an ancestor of `origin/main`.
Readiness requires the configured port to be held by the systemd service's current
`MainPID`; an unrelated UDP listener cannot make deployment succeed. Rollback retains the
previous root-owned application tree until that check passes.
