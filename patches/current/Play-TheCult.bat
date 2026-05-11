@echo off
setlocal EnableExtensions

set "LAUNCHER_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/Play-TheCult.ps1"
set "LAUNCHER_DIR=%LOCALAPPDATA%\TheCult"
set "LAUNCHER=%LAUNCHER_DIR%\Play-TheCult.ps1"

if not exist "%LAUNCHER_DIR%" mkdir "%LAUNCHER_DIR%" >NUL 2>NUL

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $u=$env:LAUNCHER_URL + '?v=' + [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); Invoke-WebRequest -Uri $u -OutFile $env:LAUNCHER -UseBasicParsing"
if errorlevel 1 (
  echo Failed to update launcher from:
  echo   %LAUNCHER_URL%
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
exit /b %ERRORLEVEL%
