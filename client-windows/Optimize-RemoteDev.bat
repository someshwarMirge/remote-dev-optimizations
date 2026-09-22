@echo off
:: ==============================================================================
:: Optimize-RemoteDev.bat
:: One-click self-elevating launcher for Windows Client Optimization
:: ==============================================================================

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Requesting Administrator privileges to optimize PC for remote cloud development...
    powershell -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)

echo ========================================================
echo Optimizing Windows Client for Remote Cloud Development...
echo ========================================================
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0optimize-for-remote-dev.ps1"
echo.
pause
