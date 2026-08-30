# Cat War server

The dedicated server uses the same authoritative Godot code and executable as the client.

Run from PowerShell after exporting the project:

```powershell
.\builds\CatWar.exe --headless -- --server --port=7777
```

On an installed copy, launch **Cat War Dedicated Server** from the Start menu or run `StartServer.cmd`. The server listens on UDP. Open the selected UDP port in the host firewall and cloud security group/router as required.

## Production Linux server

The official Linux service runs Godot headlessly under `catwar-server.service`. Install
`server/linux/catwar-update.service` and `server/linux/catwar-update.timer` to poll the
GitHub Pages update manifest every two minutes. An update is staged and tested
first. The live server then stops accepting new players, waits for active matches to
finish, swaps the application tree, and restarts. A failed readiness check rolls back to
the previous tree.

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
