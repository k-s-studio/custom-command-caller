@echo off
if /i "%~1"=="install" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1"
    goto :eof
)
if /i "%~1"=="highlighter" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install-highlighter.ps1" %2 %3
    goto :eof
)