@echo off
rem 'ccc' entry; the script is in lib\ (see SPEC).
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0lib\ccc.ps1" %* & call exit /b %%errorlevel%%
