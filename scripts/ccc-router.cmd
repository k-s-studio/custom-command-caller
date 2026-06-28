@echo off
rem Global 'ccc-router' wrapper. install.ps1 copies this into ~/.ccc; %~dp0 resolves ccc-router.ps1 beside it.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ccc-router.ps1" %*
