@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PATCH_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/patch-Z.MPQ"
set "MANIFEST_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/manifest.json"
set "PATCH_SHA256=F61B674CD898F338E5142E3417B824DA11ACF8059DFAACC5BFA54856D37D82ED"
set "PATCH_BYTES=20580970"
set "PATCH_NAME=patch-Z.MPQ"
set "ADDON_NAME=CultRedeem"
set "ADDON_TOC_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultRedeem/CultRedeem.toc"
set "ADDON_LUA_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultRedeem/CultRedeem.lua"
set "MAK_ADDON_NAME=CultMak"
set "MAK_ADDON_TOC_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultMak/CultMak.toc"
set "MAK_ADDON_LUA_URL=https://raw.githubusercontent.com/fogennnnn/The-Cult/master/patches/current/addons/CultMak/CultMak.lua"
set "RETRY_COUNT=5"

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
call :DownloadFile "%PATCH_URL%" "%PATCH%" "%PATCH_NAME%"
if errorlevel 1 (
    echo ERROR: Patch download failed after retries.
    pause
    exit /b 1
)
if not "%MANIFEST_URL%"=="" (
    call :DownloadFile "%MANIFEST_URL%" "%MANIFEST%" "manifest.json"
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
for %%F in ("%PATCH%") do set "ACTUAL_BYTES=%%~zF"
if not "%ACTUAL_BYTES%"=="%PATCH_BYTES%" (
    echo ERROR: Downloaded patch size did not match.
    echo Expected bytes: %PATCH_BYTES%
    echo Actual bytes:   %ACTUAL_BYTES%
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
for /f "usebackq tokens=*" %%H in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-FileHash -Algorithm SHA256 -LiteralPath $env:DST).Hash.ToUpperInvariant()"`) do set "INSTALLED_SHA256=%%H"
if not "%INSTALLED_SHA256%"=="%PATCH_SHA256%" (
    echo ERROR: Installed %PATCH_NAME% hash did not match expected after copy.
    echo Expected:  %PATCH_SHA256%
    echo Installed: %INSTALLED_SHA256%
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

call :DownloadFile "%ADDON_TOC_URL%" "%ADDONDIR%\CultRedeem.toc" "CultRedeem.toc"
if errorlevel 1 (
    echo ERROR: Addon file download failed: CultRedeem.toc
    pause
    exit /b 1
)
call :DownloadFile "%ADDON_LUA_URL%" "%ADDONDIR%\CultRedeem.lua" "CultRedeem.lua"
if errorlevel 1 (
    echo ERROR: Addon file download failed: CultRedeem.lua
    pause
    exit /b 1
)
for %%F in ("%ADDONDIR%\CultRedeem.toc" "%ADDONDIR%\CultRedeem.lua") do (
    if not exist "%%~fF" (
        echo ERROR: Missing addon file: %%~fF
        pause
        exit /b 1
    )
    if %%~zF LEQ 0 (
        echo ERROR: Empty addon file: %%~fF
        pause
        exit /b 1
    )
)
echo Installed addon: %ADDON_NAME%

echo Installing player addon %MAK_ADDON_NAME%...
set "MAKADDONDIR=%WOWROOT%\Interface\AddOns\%MAK_ADDON_NAME%"
if not exist "%MAKADDONDIR%" mkdir "%MAKADDONDIR%" >NUL 2>NUL
if errorlevel 1 (
    echo WARNING: Could not create addon folder:
    echo   %MAKADDONDIR%
    goto Finish
)

call :DownloadFile "%MAK_ADDON_TOC_URL%" "%MAKADDONDIR%\CultMak.toc" "CultMak.toc"
if errorlevel 1 (
    echo ERROR: Addon file download failed: CultMak.toc
    pause
    exit /b 1
)
call :DownloadFile "%MAK_ADDON_LUA_URL%" "%MAKADDONDIR%\CultMak.lua" "CultMak.lua"
if errorlevel 1 (
    echo ERROR: Addon file download failed: CultMak.lua
    pause
    exit /b 1
)
for %%F in ("%MAKADDONDIR%\CultMak.toc" "%MAKADDONDIR%\CultMak.lua") do (
    if not exist "%%~fF" (
        echo ERROR: Missing addon file: %%~fF
        pause
        exit /b 1
    )
    if %%~zF LEQ 0 (
        echo ERROR: Empty addon file: %%~fF
        pause
        exit /b 1
    )
)
echo Installed addon: %MAK_ADDON_NAME%

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

:DownloadFile
set "DL_URL=%~1"
set "DL_OUT=%~2"
set "DL_LABEL=%~3"
if "%DL_URL%"=="" (
    echo ERROR: Empty download URL for %DL_LABEL%.
    exit /b 1
)
set /a DL_TRY=0
:DownloadRetry
set /a DL_TRY+=1
echo Downloading %DL_LABEL% ^(attempt !DL_TRY!/%RETRY_COUNT%^)...
powershell -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri $env:DL_URL -OutFile $env:DL_OUT -UseBasicParsing"
if not errorlevel 1 (
    if exist "%DL_OUT%" (
        for %%F in ("%DL_OUT%") do if %%~zF GTR 0 exit /b 0
    )
)
if !DL_TRY! LSS %RETRY_COUNT% (
    ping -n 2 127.0.0.1 >NUL
    goto DownloadRetry
)
echo ERROR: Failed to download %DL_LABEL% from:
echo   %DL_URL%
exit /b 1

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
