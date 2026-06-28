@echo off
rem Repo-level bootstrap. From the clone the only thing you do is install; this .bat
rem is a DIFFERENT file from the ~/.ccc/ccc-router.cmd that install.ps1 writes, so the
rem installed 'ccc-router' (init/status/upgrade/uninstall/beauty) never carries install.
if /i "%~1"=="install" goto run
if "%~1"=="" goto run
echo Unknown command "%~1".
echo From the cloned repo, run:  ccc-router install [--beauty --vscode]
echo After installing, use init / status / upgrade / template / uninstall / beauty from any directory.
exit /b 1
:run
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
