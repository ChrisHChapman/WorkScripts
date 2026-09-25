@echo off
rem Drag a target folder onto this file, or double-click it to pick a folder.
setlocal
if "%~1"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ConsolidateForImport.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ConsolidateForImport.ps1" -TargetPath "%~1"
)
echo.
pause
