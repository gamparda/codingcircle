@echo off
setlocal EnableExtensions EnableDelayedExpansion
cd /d "%~dp0"

rem Command-line arguments are intentionally ignored: expanding %%1 in a batch file
rem permits cmd metacharacter injection. Set CATWAR_PORT for a custom port.
set "PORT=7777"
if defined CATWAR_PORT set "PORT=!CATWAR_PORT!"
set "CATWAR_VALIDATED_PORT=!PORT!"
powershell.exe -NoProfile -NonInteractive -Command "$p=$env:CATWAR_VALIDATED_PORT; if ($p -notmatch '^[0-9]{1,5}$') { exit 2 }; $n=[int]$p; if ($n -lt 1 -or $n -gt 65535) { exit 2 }"
if errorlevel 1 goto invalid_port

:validated_port
title Cat War Dedicated Server - UDP !PORT!
echo ==================================================
echo   CAT WAR DEDICATED SERVER
echo   UDP port: !PORT!
echo   Close this window or press Ctrl+C to stop.
echo ==================================================
echo.
"%~dp0CatWar.exe" --headless -- --server --port=!PORT!
set "EXIT_CODE=!ERRORLEVEL!"
echo.
echo Server stopped with exit code !EXIT_CODE!.
pause
exit /b !EXIT_CODE!

:invalid_port
echo Invalid CATWAR_PORT. Enter an integer from 1 through 65535.
exit /b 2
