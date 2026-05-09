@echo off
title DeepSeek OFF
color 0C

echo.
echo  ==========================================
echo   Switching back to Claude (Anthropic)...
echo  ==========================================
echo.

:: Kill the proxy (any node process on port 4000)
echo  Stopping DeepSeek proxy...
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":4000 "') do (
    taskkill /f /pid %%p >nul 2>&1
)

:: Remove the env var so Claude Code hits Anthropic directly
reg delete "HKCU\Environment" /v ANTHROPIC_BASE_URL /f >nul 2>&1
echo  Cleared ANTHROPIC_BASE_URL

echo.
echo  ==========================================
echo   Claude (Anthropic) is now ACTIVE
echo  ==========================================
echo.
echo  Restart Claude Code for the change to take effect.
echo.
pause
