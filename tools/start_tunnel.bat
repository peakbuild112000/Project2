@echo off
REM Double-click this file after starting a hosted session.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0start_tunnel.ps1"
pause
