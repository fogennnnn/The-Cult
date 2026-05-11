@echo off
setlocal EnableExtensions

set "LAUNCHER_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/WowCult.ps1"
set "LAUNCHER_API=https://api.github.com/repos/fogennnnn/The-Cult/contents/patches/current/WowCult.ps1?ref=master"
set "LAUNCHER_DIR=%LOCALAPPDATA%\TheCult"
set "LAUNCHER=%LAUNCHER_DIR%\WowCult.ps1"
set "LAUNCHER_FETCH=%LAUNCHER_URL%?v=%RANDOM%%RANDOM%"

if not exist "%LAUNCHER_DIR%" mkdir "%LAUNCHER_DIR%" >NUL 2>NUL
if exist "%LAUNCHER%" del /F /Q "%LAUNCHER%" >NUL 2>NUL

powershell -NoProfile -ExecutionPolicy Bypass -Command "try { $ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $headers=@{'User-Agent'='TheCultLauncher'}; $res=Invoke-WebRequest -Uri $env:LAUNCHER_API -Headers $headers -UseBasicParsing; $json=$res.Content | ConvertFrom-Json; $bytes=[Convert]::FromBase64String(($json.content -replace '\s','')); [IO.File]::WriteAllBytes($env:LAUNCHER,$bytes); exit 0 } catch { try { Invoke-WebRequest -Uri $env:LAUNCHER_FETCH -OutFile $env:LAUNCHER -UseBasicParsing; exit 0 } catch { Write-Host $_; exit 1 } }"
if errorlevel 1 (
  echo Failed to update launcher from:
  echo   %LAUNCHER_URL%
  pause
  exit /b 1
)
if not exist "%LAUNCHER%" (
  echo Failed to write launcher file:
  echo   %LAUNCHER%
  pause
  exit /b 1
)

powershell -NoProfile -ExecutionPolicy Bypass -File "%LAUNCHER%" %*
exit /b %ERRORLEVEL%

