@echo off
title DeepSeek ON
color 0A

echo.
echo  ==========================================
echo   Switching Claude Code to DeepSeek...
echo  ==========================================
echo.

:: Read API key saved by the GUI (deepseek-tray.ps1)
set KEY_FILE=%~dp0deepseek-key.txt
if not exist "%KEY_FILE%" (
    echo  No API key found.
    echo  Open the DeepSeek Switcher GUI and enter your key there first.
    echo.
    pause
    exit /b 1
)
set /p DEEPSEEK_API_KEY=<"%KEY_FILE%"
if "%DEEPSEEK_API_KEY%"=="" (
    echo  API key file is empty.
    echo  Open the DeepSeek Switcher GUI and enter your key there first.
    echo.
    pause
    exit /b 1
)

:: Kill any process already on port 4000
echo  Clearing port 4000...
for /f "tokens=5" %%p in ('netstat -aon 2^>nul ^| findstr ":4000 "') do (
    taskkill /f /pid %%p >nul 2>&1
)

:: Start the Node.js proxy completely hidden (no window)
echo  Starting DeepSeek proxy...
set PROXY_DIR=%~dp0
wscript "%PROXY_DIR%start-proxy.vbs" "%DEEPSEEK_API_KEY%" "%PROXY_DIR%deepseek-proxy.js"

:: Brief wait for the server to boot
timeout /t 2 /nobreak >nul

:: Point Claude Code at the local proxy
setx ANTHROPIC_BASE_URL "http://localhost:4000" >nul
echo  Set ANTHROPIC_BASE_URL=http://localhost:4000

echo.
echo  ==========================================
echo   DeepSeek is now ACTIVE
echo  ==========================================
echo.
echo  Restart Claude Code for the change to take effect.
echo.
pause
