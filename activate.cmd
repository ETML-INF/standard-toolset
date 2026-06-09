@echo off
where pwsh >nul 2>&1
if %errorlevel%==0 (
    pwsh -ExecutionPolicy Bypass -File "%~dp0toolset.ps1"
) else (
    powershell -ExecutionPolicy Bypass -File "%~dp0toolset.ps1"
)
