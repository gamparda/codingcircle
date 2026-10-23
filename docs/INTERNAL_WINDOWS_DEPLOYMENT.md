# Internal managed Windows client

This package is for computers managed by the deploying administrator. It includes the Windows game client and PC Remote Agent. The installer has a **selected by default** agent task that names the management server and its command, file, screen, and input permissions. Unchecking the task skips agent installation. The agent remains visible in the tray and Windows Installed Apps, with Start menu entries to stop or uninstall it. Previous task choices are preserved on upgrades.

The public Windows installer, public update workflow, Android APK, and content packs do not include the agent. Do not publish `dist/managed` to the public update channel. The separate agent installation survives normal game updates; uninstall it separately when a PC leaves management.

## Build

Run the normal Windows build first, then package the internal installer:

```powershell
.\tools\build_release.ps1
.\tools\build_managed_client.ps1
```

The second command uses authenticated `gh` access to download the private agent release pinned in `tools/managed_agent.json`. Alternatively pass `-AgentPath C:\path\PCRemoteAgent.exe`. Both paths verify the same SHA-256 before compiling. No agent binary, controller token, or deployment credential is committed to this repository.

The output is `dist/managed/CatWarManagedSetup.exe`. `PCRemoteAgentSetup.exe` in the same directory is also available for agent-only maintenance. These files are not copied by the public build workflow.

## Bot deployment

Run in the intended signed-in Windows user's session, not as SYSTEM or another administrator's account. This is a per-user interactive desktop agent and needs no elevation:

```powershell
$process = Start-Process -FilePath .\CatWarManagedSetup.exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-', '/MERGETASKS=pcremoteagent', '/INSTALLPCREMOTEAGENT=1' -Wait -PassThru
if ($process.ExitCode -ne 0) { throw "Managed install failed: $($process.ExitCode)" }
```

The explicit `/INSTALLPCREMOTEAGENT=1` option authorizes first-time unattended deployment. Without it, silent game updates install the agent only if its separate managed installation already exists. The interactive default checkbox never silently opts existing game users into remote access.

The agent installs to `%LOCALAPPDATA%\ChzzkAutoWatch`, starts immediately and on user login, and registers with `https://pc-api.ruellyya.kr`. Fresh installations show a tray icon and disable the optional direct LAN listener. Existing `config.json`, automation tokens, and device identity are preserved. An agent installation failure fails the enclosing game installation instead of reporting success.

Use **PC Remote Agent → Stop PC Remote Agent** or its tray menu to stop it. Remove **PC Remote Agent (Internal Management)** from Windows Installed Apps to remove the executable and login shortcut. Configuration and identity remain for reinstallation; remove a retired PC from the controller's device list to revoke its registration.
