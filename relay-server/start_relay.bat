@echo off
REM ============================================================
REM 星璃音乐 中转服务器 一键启动 (Xingli Relay Server)
REM ------------------------------------------------------------
REM 绑 0.0.0.0:8765 —— 监听所有网卡：
REM   · 本机 localhost(127.0.0.1)
REM   · 本机 LAN (本机 WLAN IP，如 192.168.1.248)
REM   · 同 /24 子网设备 (如 192.168.1.125) 均可连
REM 客户端大厅选「中转服务器」，填 ws://<本机LAN_IP>:8765/ws
REM ------------------------------------------------------------
setlocal
set RELAY_DIR=%~dp0
set NODE_EXE=C:\Users\Administrator\.workbuddy\binaries\node\versions\22.22.2\node.exe
set HOST=0.0.0.0
set PORT=8765

if not exist "%NODE_EXE%" (
  echo [ERROR] node.exe not found at %NODE_EXE%
  echo         edit this bat to point NODE_EXE at your node install.
  pause
  exit /b 1
)

echo Starting Xingli relay server on %HOST%:%PORT% ...
echo (Ctrl+C to stop; health: http://127.0.0.1:%PORT%/healthz )
"%NODE_EXE%" "%RELAY_DIR%index.js"
endlocal
