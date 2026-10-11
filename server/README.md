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

If completed replays awaiting persistence reach 16 recordings or 100,000 commands, the
server pauses new battles (quick matches, room starts and rematches) with a retryable storage
message. Existing battles, reconnects, spectators and room chat continue. Waiting quick-match
players keep their queue position and pairing resumes after the periodic writes recover.
This prevents an ongoing outage from accepting more battles once the backlog reaches its
threshold; already active battles may still finish and add pending records. It is not a hard
memory limit. `REPLAY_BACKLOG` logs pause/recovery transitions; `server-status.json` exposes
`accepting_matches`, `replay_backlog_full` and `pending_replay_commands` separately from the
update-related `accepting_players` flag. Update draining still takes priority after recovery.

Local match archives keep the newest 50 readable files. Unreadable originals are preserved
for manual recovery or deletion and do not consume those slots. Archive cleanup failures log
`REPLAY_TRIM_PENDING` and retry every 30 seconds as well as after the next archive save.
The server's in-memory diagnostic path history also retains only the latest 50 successful
archive paths. This history does not control pending writes or delete files.

## Assist servers and helper PCs

Assist servers and helper PCs may connect and take over batch work such as balance experiments. There is no token;
only light limits apply. Set `CATWAR_ASSIST=off` (for example in `/etc/catwar/server.env`) to refuse them. The main server still does the
work itself at low priority when nobody helps. Finished job results are written to `<state dir>/jobs/`. See
`docs/ASSIST_DESIGN.md`.

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
