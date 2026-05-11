#!/usr/bin/env python3
from __future__ import annotations

"""Build a minimal player-facing VMaNGOS client patch bundle.

The development client can drift far away from a clean 1.12.1 install. This
script packages the files players need and can publish a stable repo-backed
current patch where players only download one installer batch file.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parent
DEFAULT_DBC_TOOLS = REPO_ROOT.parent / "vmangos-dbc-inspect"
DEFAULT_RELEASE_DIR = REPO_ROOT / "patches" / "releases"
DEFAULT_CURRENT_DIR = REPO_ROOT / "patches" / "current"
DEFAULT_PLAYER_SCRIPT = REPO_ROOT / "install-client-patch.bat"
DEFAULT_ADDON_SOURCE_DIR = REPO_ROOT / "addons"

PATCH_NAME = "patch-Z.MPQ"
PLAYER_ADDON_NAME = "CultRedeem"
PLAYER_ADDON_FILES = ["CultRedeem.toc", "CultRedeem.lua"]
PLAYER_ADDONS = {
    "CultRedeem": ["CultRedeem.toc", "CultRedeem.lua"],
    "CultMak": ["CultMak.toc", "CultMak.lua"],
}

BASE_ARCHIVE_FILES = [
    ("Spell.patched.dbc", "DBFilesClient\\Spell.dbc"),
    ("SkillLineAbility.patched.dbc", "DBFilesClient\\SkillLineAbility.dbc"),
    ("SpellItemEnchantment.patched.dbc", "DBFilesClient\\SpellItemEnchantment.dbc"),
    ("ItemDisplayInfo.patched.dbc", "DBFilesClient\\ItemDisplayInfo.dbc"),
    ("ItemVisuals.patched.dbc", "DBFilesClient\\ItemVisuals.dbc"),
    ("ItemVisualEffects.patched.dbc", "DBFilesClient\\ItemVisualEffects.dbc"),
    ("Sword_2H_Ashbringer02.noparticles.m2", "Item\\ObjectComponents\\Weapon\\Sword_2H_Ashbringer02.m2"),
]

BUILDER_TEXTURE_FILES = [
    ("SPELLS__VDB1.BLP", "SPELLS\\VDB1.BLP"),
    ("SPELLS__VDB2.BLP", "SPELLS\\VDB2.BLP"),
    ("ITEM__OBJECTCOMPONENTS__AMMO__VDBLKGLOW.BLP", "ITEM\\OBJECTCOMPONENTS\\AMMO\\VDBLKGLOW.BLP"),
    ("SPELLS__VDBALL.BLP", "SPELLS\\VDBALL.BLP"),
    ("ITEM__OBJECTCOMPONENTS__WEAPON__VOIDBLADE01.BLP", "ITEM\\OBJECTCOMPONENTS\\WEAPON\\VOIDBLADE01.BLP"),
    ("ITEM__OBJECTCOMPONENTS__WEAPON__ASHBRINGER02.BLP", "ITEM\\OBJECTCOMPONENTS\\WEAPON\\ASHBRINGER02.BLP"),
]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def rel(path: Path) -> str:
    try:
        return str(path.relative_to(REPO_ROOT.parent))
    except ValueError:
        return str(path)


def read_legendary_manifest(dbc_tools: Path) -> list[tuple[Path, str]]:
    manifest_path = dbc_tools / "legendary_void_patch_files.txt"
    entries: list[tuple[Path, str]] = []
    if not manifest_path.exists():
        return entries
    for raw_line in manifest_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        source, archive_path = line.split("|", 1)
        entries.append((Path(source), archive_path))
    return entries


def expected_archive_files(dbc_tools: Path) -> list[dict]:
    entries: list[tuple[Path, str, str]] = []
    entries.extend((dbc_tools / source, archive_path, "core") for source, archive_path in BASE_ARCHIVE_FILES)
    entries.extend((dbc_tools / source, archive_path, "texture") for source, archive_path in BUILDER_TEXTURE_FILES)
    entries.extend((source, archive_path, "legendary_void") for source, archive_path in read_legendary_manifest(dbc_tools))

    seen: set[str] = set()
    result: list[dict] = []
    for source_path, archive_path, group in entries:
        key = archive_path.lower()
        if key in seen:
            continue
        seen.add(key)
        exists = source_path.exists()
        row = {
            "archive_path": archive_path,
            "source_path": str(source_path),
            "source_repo_path": rel(source_path),
            "group": group,
            "exists": exists,
        }
        if exists:
            row["bytes"] = source_path.stat().st_size
            row["sha256"] = sha256_file(source_path)
        result.append(row)
    return result


def run_builder(dbc_tools: Path, patch_path: Path) -> None:
    builder = dbc_tools / "build_client_patch_mpq.py"
    if not builder.exists():
        raise FileNotFoundError(builder)
    env = os.environ.copy()
    env["PATCH_OUTPUT_PATH"] = str(patch_path)
    subprocess.run([sys.executable, str(builder), str(patch_path)], cwd=str(dbc_tools), env=env, check=True)


def git_output(args: list[str]) -> str:
    try:
        return subprocess.check_output(["git", *args], cwd=str(REPO_ROOT), text=True, stderr=subprocess.DEVNULL).strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return ""


def github_raw_base_from_remote(remote_url: str, branch: str) -> str:
    if remote_url.startswith("git@github.com:"):
        repo = remote_url.split(":", 1)[1]
        if repo.endswith(".git"):
            repo = repo[:-4]
        return f"https://raw.githubusercontent.com/{repo}/{branch}"

    parsed = urlparse(remote_url)
    if parsed.netloc.lower() != "github.com":
        return ""
    repo = parsed.path.strip("/")
    if repo.endswith(".git"):
        repo = repo[:-4]
    if not repo:
        return ""
    return f"https://raw.githubusercontent.com/{repo}/{branch}"


def default_download_base_url(current_dir: Path) -> str:
    remote_url = git_output(["config", "--get", "remote.origin.url"])
    branch = git_output(["branch", "--show-current"]) or "master"
    raw_base = github_raw_base_from_remote(remote_url, branch)
    if not raw_base:
        return ""
    current_rel = current_dir.relative_to(REPO_ROOT).as_posix()
    return f"{raw_base.rstrip('/')}/{current_rel}"


def write_text_files(release_dir: Path, patch_file: Path, manifest: dict, download_base_url: str) -> None:
    patch_hash = manifest["patch"]["sha256"]
    patch_bytes = manifest["patch"]["bytes"]
    patch_url = f"{download_base_url.rstrip('/')}/{PATCH_NAME}" if download_base_url else ""
    manifest_url = f"{download_base_url.rstrip('/')}/manifest.json" if download_base_url else ""
    addon_base_url = f"{download_base_url.rstrip('/')}/addons/CultRedeem" if download_base_url else ""
    addon_toc_url = f"{addon_base_url}/CultRedeem.toc" if addon_base_url else ""
    addon_lua_url = f"{addon_base_url}/CultRedeem.lua" if addon_base_url else ""
    mak_addon_base_url = f"{download_base_url.rstrip('/')}/addons/CultMak" if download_base_url else ""
    mak_addon_toc_url = f"{mak_addon_base_url}/CultMak.toc" if mak_addon_base_url else ""
    mak_addon_lua_url = f"{mak_addon_base_url}/CultMak.lua" if mak_addon_base_url else ""

    installer = f"""@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "PATCH_URL={patch_url}"
set "MANIFEST_URL={manifest_url}"
set "PATCH_SHA256={patch_hash.upper()}"
set "PATCH_BYTES={patch_bytes}"
set "PATCH_NAME={PATCH_NAME}"
set "ADDON_NAME={PLAYER_ADDON_NAME}"
set "ADDON_TOC_URL={addon_toc_url}"
set "ADDON_LUA_URL={addon_lua_url}"
set "MAK_ADDON_NAME=CultMak"
set "MAK_ADDON_TOC_URL={mak_addon_toc_url}"
set "MAK_ADDON_LUA_URL={mak_addon_lua_url}"
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
if not defined WOWDATA call :TryPath "C:\\Games\\wow\\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "C:\\Games\\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "C:\\Games\\World of Warcraft"
if not defined WOWDATA call :TryPath "%ProgramFiles(x86)%\\World of Warcraft"
if not defined WOWDATA call :TryPath "%ProgramFiles%\\World of Warcraft"
if not defined WOWDATA call :TryPath "%USERPROFILE%\\Games\\World of Warcraft Vanilla"
if not defined WOWDATA call :TryPath "%USERPROFILE%\\Desktop\\World of Warcraft"
if not defined WOWDATA call :TryPath "%USERPROFILE%\\Downloads\\World of Warcraft"

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
    echo Expected files like WoW.exe plus Data\\patch.MPQ, or Data\\common.MPQ plus patch.MPQ.
    echo.
    goto PromptForWow
)

:InstallPatch
set "WORK=%TEMP%\\vmangos-client-patch"
if exist "%WORK%" rmdir /S /Q "%WORK%" >NUL 2>NUL
mkdir "%WORK%" >NUL 2>NUL
if errorlevel 1 (
    echo ERROR: Could not create temp folder:
    echo   %WORK%
    pause
    exit /b 1
)
set "PATCH=%WORK%\\%PATCH_NAME%"
set "MANIFEST=%WORK%\\manifest.json"

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

set "DST=%WOWDATA%\\%PATCH_NAME%"
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
if exist "%CAND%\\Wow.exe" if exist "%CAND%\\Data\\patch.MPQ" set "WOWDATA=%CAND%\\Data" & exit /b 0
if exist "%CAND%\\WoW.exe" if exist "%CAND%\\Data\\patch.MPQ" set "WOWDATA=%CAND%\\Data" & exit /b 0
if exist "%CAND%\\Wow.exe" if exist "%CAND%\\Data\\common.MPQ" set "WOWDATA=%CAND%\\Data" & exit /b 0
if exist "%CAND%\\WoW.exe" if exist "%CAND%\\Data\\common.MPQ" set "WOWDATA=%CAND%\\Data" & exit /b 0
if exist "%CAND%\\common.MPQ" if exist "%CAND%\\patch.MPQ" set "WOWDATA=%CAND%" & exit /b 0
if exist "%CAND%\\patch.MPQ" if exist "%CAND%\\dbc.MPQ" set "WOWDATA=%CAND%" & exit /b 0
exit /b 0

:PickBackupName
set "BAK=%~1\\patch-Z.before.MPQ"
set /a BAKNUM=0
:BackupNameLoop
if not exist "!BAK!" exit /b 0
set /a BAKNUM+=1
set "BAK=%~1\\patch-Z.before-!BAKNUM!.MPQ"
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
"""
    with (release_dir / "install-client-patch.bat").open("w", encoding="utf-8", newline="\n") as handle:
        handle.write(installer)

    rows = ["archive_path\tsource_repo_path\tbytes\tsha256\tgroup"]
    for entry in manifest["expected_archive_files"]:
        if not entry["exists"]:
            continue
        rows.append(
            "\t".join(
                [
                    entry["archive_path"],
                    entry["source_repo_path"],
                    str(entry.get("bytes", "")),
                    entry.get("sha256", ""),
                    entry["group"],
                ]
            )
        )
    (release_dir / "required-files.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")


def publish_current(release_dir: Path, current_dir: Path, player_script: Path) -> None:
    current_dir.mkdir(parents=True, exist_ok=True)
    for name in [PATCH_NAME, "manifest.json", "required-files.tsv", "install-client-patch.bat"]:
        source = release_dir / name
        if source.exists():
            shutil.copy2(source, current_dir / name)
    src_addons = release_dir / "addons"
    dst_addons = current_dir / "addons"
    if src_addons.exists():
        if dst_addons.exists():
            shutil.rmtree(dst_addons)
        shutil.copytree(src_addons, dst_addons)
    shutil.copy2(release_dir / "install-client-patch.bat", player_script)


def run_git_command(args: list[str]) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=str(REPO_ROOT),
        check=True,
        text=True,
        capture_output=True,
    )
    return (result.stdout or "").strip()


def git_sync_publish_current(manifest: dict, label: str) -> None:
    run_git_command(["add", "addons", "patches/current", "install-client-patch.bat"])
    status = run_git_command(["status", "--porcelain", "--", "addons", "patches/current", "install-client-patch.bat"])
    if not status:
        print("git_publish=no_changes")
        return

    branch = git_output(["branch", "--show-current"]) or "master"
    patch_hash = manifest.get("patch", {}).get("sha256", "")[:12]
    clean_label = label.strip().replace(" ", "-") if label.strip() else "auto"
    message = f"deploy client patch {clean_label} {patch_hash}".strip()
    run_git_command(["commit", "-m", message])
    run_git_command(["push", "origin", branch])
    print(f"git_publish=ok branch={branch} commit_message={message}")


def stage_player_addons(addon_source_dir: Path, release_dir: Path) -> dict[str, list[str]]:
    staged: dict[str, list[str]] = {}
    for addon_name, addon_files in PLAYER_ADDONS.items():
        source_dir = addon_source_dir / addon_name
        if not source_dir.exists():
            raise FileNotFoundError(source_dir)
        destination = release_dir / "addons" / addon_name
        destination.mkdir(parents=True, exist_ok=True)
        copied: list[str] = []
        for file_name in addon_files:
            src = source_dir / file_name
            if not src.exists():
                raise FileNotFoundError(src)
            shutil.copy2(src, destination / file_name)
            copied.append(str((destination / file_name).relative_to(release_dir)).replace("\\", "/"))
        staged[addon_name] = copied
    return staged


def write_zip(release_dir: Path, zip_path: Path) -> None:
    if zip_path.exists():
        zip_path.unlink()
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(release_dir.iterdir()):
            if path == zip_path:
                continue
            archive.write(path, path.name)


def main() -> int:
    parser = argparse.ArgumentParser(description="Package a minimal player client patch bundle.")
    parser.add_argument("--dbc-tools", default=str(DEFAULT_DBC_TOOLS), help="Path to vmangos-dbc-inspect.")
    parser.add_argument("--output-root", default=str(DEFAULT_RELEASE_DIR), help="Release output root.")
    parser.add_argument("--label", default="", help="Optional release label suffix.")
    parser.add_argument("--use-existing-mpq", default="", help="Use an existing MPQ instead of rebuilding one.")
    parser.add_argument("--no-zip", action="store_true", help="Do not create a zip wrapper.")
    parser.add_argument("--download-base-url", default="", help="Base URL containing patch-Z.MPQ and manifest.json.")
    parser.add_argument("--publish-current", action="store_true", help="Refresh patches/current and root installer script.")
    parser.add_argument("--no-git-push", action="store_true", help="Do not auto commit/push when publishing current patch.")
    parser.add_argument("--current-dir", default=str(DEFAULT_CURRENT_DIR), help="Repo path for stable current patch files.")
    parser.add_argument("--player-script", default=str(DEFAULT_PLAYER_SCRIPT), help="Standalone player installer .bat path.")
    parser.add_argument("--addon-source-dir", default=str(DEFAULT_ADDON_SOURCE_DIR), help="Path containing addon source folders.")
    args = parser.parse_args()

    dbc_tools = Path(args.dbc_tools)
    if not dbc_tools.exists():
        raise FileNotFoundError(dbc_tools)
    current_dir = Path(args.current_dir)
    player_script = Path(args.player_script)
    addon_source_dir = Path(args.addon_source_dir)
    download_base_url = args.download_base_url.strip()
    if not download_base_url:
        download_base_url = default_download_base_url(current_dir)

    stamp = time.strftime("%Y%m%d-%H%M%S")
    label_suffix = ("-" + args.label.strip().replace(" ", "-")) if args.label.strip() else ""
    release_dir = Path(args.output_root) / f"client-patch-{stamp}{label_suffix}"
    release_dir.mkdir(parents=True, exist_ok=False)

    patch_file = release_dir / PATCH_NAME
    if args.use_existing_mpq:
        source_mpq = Path(args.use_existing_mpq)
        if not source_mpq.exists():
            raise FileNotFoundError(source_mpq)
        shutil.copy2(source_mpq, patch_file)
    else:
        run_builder(dbc_tools, patch_file)

    expected_files = expected_archive_files(dbc_tools)
    missing_required = [
        entry["archive_path"]
        for entry in expected_files
        if not entry["exists"] and entry["group"] in {"core"}
    ]
    if missing_required:
        raise RuntimeError("Missing required patch inputs: " + ", ".join(missing_required))

    manifest = {
        "kind": "vmangos-client-patch-bundle",
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "patch": {
            "file": PATCH_NAME,
            "bytes": patch_file.stat().st_size,
            "sha256": sha256_file(patch_file),
        },
        "source": {
            "dbc_tools": str(dbc_tools),
            "builder": str(dbc_tools / "build_client_patch_mpq.py"),
            "used_existing_mpq": args.use_existing_mpq or None,
        },
        "install": {
            "target": "WoW 1.12.1 Data folder",
            "download_base_url": download_base_url or None,
            "notes": [
                "Close WoW before installing.",
                "Players only need install-client-patch.bat; it downloads patch-Z.MPQ from the repo.",
                "Delete WDB if cached item/spell text looks stale.",
            ],
        },
        "expected_archive_files": expected_files,
    }

    write_text_files(release_dir, patch_file, manifest, download_base_url)
    staged_addons = stage_player_addons(addon_source_dir, release_dir)
    manifest["player_addon"] = {
        "name": PLAYER_ADDON_NAME,
        "files": staged_addons[PLAYER_ADDON_NAME],
    }
    manifest["player_addons"] = [
        {"name": addon_name, "files": files}
        for addon_name, files in staged_addons.items()
    ]
    (release_dir / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    if args.publish_current:
        publish_current(release_dir, current_dir, player_script)
        if not args.no_git_push:
            git_sync_publish_current(manifest, args.label)

    zip_path = release_dir.with_suffix(".zip")
    if not args.no_zip:
        write_zip(release_dir, zip_path)

    print(f"release_dir={release_dir}")
    print(f"patch={patch_file}")
    print(f"sha256={manifest['patch']['sha256']}")
    print(f"download_base_url={download_base_url or '(none)'}")
    if args.publish_current:
        print(f"current_dir={current_dir}")
        print(f"player_script={player_script}")
    if not args.no_zip:
        print(f"zip={zip_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
