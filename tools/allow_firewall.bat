@echo off
REM Run as Administrator to let LAN players reach the host on port 9080.
netsh advfirewall firewall add rule name="Chroma Chameleon 9080" dir=in action=allow protocol=TCP localport=9080
if errorlevel 1 (
  echo Failed to add firewall rule. Right-click this file and choose "Run as administrator".
) else (
  echo Firewall rule added for TCP port 9080.
)
pause
