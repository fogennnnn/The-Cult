@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PATCH_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/patch-Z.MPQ"
set "MANIFEST_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/manifest.json"
set "PATCH_SHA256=E91B6E51686B229E189A513F00D3A6E995528EF2C6B26A4DAA0E08CD97EA3EB3"
set "PATCH_BYTES=20576679"
set "PATCH_NAME=patch-Z.MPQ"
set "ADDON_NAME=CultRedeem"
set "ADDON_TOC_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultRedeem/CultRedeem.toc"
set "ADDON_LUA_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultRedeem/CultRedeem.lua"

call :ShowIntro
echo VMaNGOS one-file client patch installer
echo.
echo Tips:
echo   - Close WoW before installing. This script will stop if WoW.exe is running.
echo   - Players only need this .bat. It downloads the current patch from the repo.
echo   - If auto-detect fails, drag your WoW folder onto this .bat or paste it when asked.
echo   - If item or spell text looks stale after installing, delete the WDB folder beside WoW.exe.
echo   - This installs only %PATCH_NAME%; it does not replace patch.MPQ, model.MPQ, texture.MPQ, maps, or account files.
echo.
echo Patch:
echo   file: %PATCH_NAME%
echo   bytes: %PATCH_BYTES%
echo   sha256: %PATCH_SHA256%
echo   url: %PATCH_URL%
echo.

if "%PATCH_URL%"=="" (
    echo ERROR: This installer was built without a download URL.
    echo Rebuild with --download-base-url or publish with --publish-current from the git repo.
    pause
    exit /b 1
)

tasklist /FI "IMAGENAME eq WoW.exe" 2>NUL | find /I "WoW.exe" >NUL
if not errorlevel 1 (
    echo ERROR: WoW.exe is running. Close WoW completely, then run this again.
    pause
    exit /b 1
)

set "WOWDATA="
if not "%~1"=="" call :TryPath "%~1"
if not defined WOWDATA call :TryPath "%CD%"
if not defined WOWDATA call :TryPath "%~dp0"
if not defined WOWDATA call :TryPath "%~dp0.."
if not defined WOWDATA call :TryPath "C:\Games\wow\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "C:\Games\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "C:\Games\World of Warcraft"
if not defined WOWDATA call :TryPath "%ProgramFiles(x86)%\World of Warcraft"
if not defined WOWDATA call :TryPath "%ProgramFiles%\World of Warcraft"
if not defined WOWDATA call :TryPath "%USERPROFILE%\Games\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "%USERPROFILE%\Desktop\World of Warcraft"
if not defined WOWDATA call :TryPath "%USERPROFILE%\Downloads\World of Warcraft"

:PromptForWow
if defined WOWDATA goto InstallPatch
echo Could not auto-detect your Vanilla WoW folder.
echo Paste either the WoW folder path or its Data folder path.
set /p "USERPATH=Path: "
if "%USERPATH%"=="" (
    echo No path entered. Cancelled.
    pause
    exit /b 1
)
call :TryPath "%USERPATH%"
if not defined WOWDATA (
    echo That did not look like a Vanilla WoW folder.
    echo Expected files like WoW.exe plus Data\patch.MPQ, or Data\common.MPQ plus patch.MPQ.
    echo.
    goto PromptForWow
)

:InstallPatch
set "WORK=%TEMP%\vmangos-client-patch"
if exist "%WORK%" rmdir /S /Q "%WORK%" >NUL 2>NUL
mkdir "%WORK%" >NUL 2>NUL
if errorlevel 1 (
    echo ERROR: Could not create temp folder:
    echo   %WORK%
    pause
    exit /b 1
)
set "PATCH=%WORK%\%PATCH_NAME%"
set "MANIFEST=%WORK%\manifest.json"

echo Downloading current patch from repo...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:PATCH_URL -OutFile $env:PATCH -UseBasicParsing; if ($env:MANIFEST_URL) { Invoke-WebRequest -Uri $env:MANIFEST_URL -OutFile $env:MANIFEST -UseBasicParsing }"
if errorlevel 1 (
    echo ERROR: Download failed.
    echo Tips:
    echo   - Check your internet connection.
    echo   - If Windows blocks the script, right-click it, open Properties, and Unblock it.
    echo   - If the repo moved, download the newest installer .bat from the server.
    pause
    exit /b 1
)

for /f "usebackq tokens=*" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath $env:PATCH).Hash.ToUpperInvariant()"`) do set "ACTUAL_SHA256=%%H"
if not "%ACTUAL_SHA256%"=="%PATCH_SHA256%" (
    echo ERROR: Downloaded patch hash did not match.
    echo Expected: %PATCH_SHA256%
    echo Actual:   %ACTUAL_SHA256%
    echo The download may be incomplete or the repo file may not match this installer.
    pause
    exit /b 1
)

echo Found WoW Data folder:
echo   %WOWDATA%
echo.

set "DST=%WOWDATA%\%PATCH_NAME%"
if exist "%DST%" (
    call :PickBackupName "%WOWDATA%"
    echo Backing up existing %PATCH_NAME% to:
    echo   !BAK!
    copy /Y "%DST%" "!BAK!" >NUL
    if errorlevel 1 (
        echo ERROR: Could not back up the existing %PATCH_NAME%.
        pause
        exit /b 1
    )
)

copy /Y "%PATCH%" "%DST%" >NUL
if errorlevel 1 (
    echo ERROR: Could not copy %PATCH_NAME% into:
    echo   %WOWDATA%
    pause
    exit /b 1
)

echo Installed %PATCH_NAME%.
echo.
echo Final tip: if tooltips, item names, or spell text look stale, close WoW and delete:
echo   the WDB folder beside WoW.exe
echo.
echo Installing player addon %ADDON_NAME%...
set "WOWROOT=%WOWDATA%\.."
set "ADDONDIR=%WOWROOT%\Interface\AddOns\%ADDON_NAME%"
if not exist "%ADDONDIR%" mkdir "%ADDONDIR%" >NUL 2>NUL
if errorlevel 1 (
    echo WARNING: Could not create addon folder:
    echo   %ADDONDIR%
    goto Finish
)

powershell -NoProfile -ExecutionPolicy Bypass -Command "$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:ADDON_TOC_URL -OutFile ($env:ADDONDIR + '\CultRedeem.toc') -UseBasicParsing; Invoke-WebRequest -Uri $env:ADDON_LUA_URL -OutFile ($env:ADDONDIR + '\CultRedeem.lua') -UseBasicParsing"
if errorlevel 1 (
    echo WARNING: Addon download failed. Patch is installed, but addon was skipped.
    echo You can re-run later or install addon manually into Interface\AddOns\%ADDON_NAME%.
    goto Finish
)
echo Installed addon: %ADDON_NAME%

:Finish
echo.
pause
exit /b 0

:TryPath
set "CAND=%~1"
if not defined CAND exit /b 0
if exist "%CAND%\Wow.exe" if exist "%CAND%\Data\patch.MPQ" set "WOWDATA=%CAND%\Data" & exit /b 0
if exist "%CAND%\WoW.exe" if exist "%CAND%\Data\patch.MPQ" set "WOWDATA=%CAND%\Data" & exit /b 0
if exist "%CAND%\Wow.exe" if exist "%CAND%\Data\common.MPQ" set "WOWDATA=%CAND%\Data" & exit /b 0
if exist "%CAND%\WoW.exe" if exist "%CAND%\Data\common.MPQ" set "WOWDATA=%CAND%\Data" & exit /b 0
if exist "%CAND%\common.MPQ" if exist "%CAND%\patch.MPQ" set "WOWDATA=%CAND%" & exit /b 0
if exist "%CAND%\patch.MPQ" if exist "%CAND%\dbc.MPQ" set "WOWDATA=%CAND%" & exit /b 0
exit /b 0

:PickBackupName
set "BAK=%~1\patch-Z.before.MPQ"
set /a BAKNUM=0
:BackupNameLoop
if not exist "!BAK!" exit /b 0
set /a BAKNUM+=1
set "BAK=%~1\patch-Z.before-!BAKNUM!.MPQ"
goto BackupNameLoop

:ShowIntro
cls
echo.
echo        [ The Cult Client Patch ]
echo.
echo              .-.
echo             (   )
echo              '-'
echo          summoning patch
ping -n 2 127.0.0.1 >NUL
cls
echo.
echo        [ The Cult Client Patch ]
echo.
echo            .--*--.
echo           (  ***  )
echo            '--*--'
echo          summoning patch.
ping -n 2 127.0.0.1 >NUL
cls
echo.
echo        [ The Cult Client Patch ]
echo.
echo          .---***---.
echo         (  *******  )
echo          '---***---'
echo          summoning patch..
ping -n 2 127.0.0.1 >NUL
cls
exit /b 0
