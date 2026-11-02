@echo off
rem 'ccc-router' entry; the script is in lib\ (see SPEC).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\ccc-router.ps1" %* & call exit /b %%errorlevel%%
