@echo off
setlocal EnableExtensions
cd /d "%~dp0"

rem Opens the assist server window (shows the live log and lets you pick what work to accept).
rem Command-line arguments are intentionally ignored, for the same reason as in StartServer.cmd.
title Keepfall Assist Server
start "" "%~dp0CatWar.exe" -- --assist
exit /b 0
