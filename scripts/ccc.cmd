@echo off
rem Global 'ccc' wrapper. install.ps1 copies this into ~/.ccc; %~dp0 resolves ccc.ps1 beside it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc.ps1" %*
