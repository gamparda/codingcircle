# Cat War server

The dedicated server uses the same authoritative Godot code and executable as the client.

Run from PowerShell after exporting the project:

```powershell
.\builds\CatWar.exe --headless -- --server --port=7777
```

On an installed copy, launch **Cat War Dedicated Server** from the Start menu or run `StartServer.cmd`. The server listens on UDP. Open the selected UDP port in the host firewall and cloud security group/router as required.
