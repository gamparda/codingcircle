@echo off
setlocal
cd /d "%~dp0"
set "PORT=%~1"
if "%PORT%"=="" set "PORT=7777"
title Cat War Dedicated Server - UDP %PORT%
echo ==================================================
echo   CAT WAR DEDICATED SERVER
echo   UDP port: %PORT%
echo   Close this window or press Ctrl+C to stop.
echo ==================================================
echo.
"%~dp0CatWar.exe" --headless -- --server --port=%PORT%
set "EXIT_CODE=%ERRORLEVEL%"
echo.
echo Server stopped with exit code %EXIT_CODE%.
pause
exit /b %EXIT_CODE%
