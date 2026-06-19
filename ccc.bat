@echo off
if /i "%~1"=="install" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\install.ps1" %2 %3 %4
    goto :eof
)