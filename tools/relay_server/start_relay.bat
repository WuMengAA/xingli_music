@echo off
REM Manual foreground start of Xingli relay server (listens on 0.0.0.0:8092, path /ws).
REM Ctrl+C to stop. For persistent run, use install_autostart.ps1 instead.
cd /d "%~dp0"
relay_server.exe
