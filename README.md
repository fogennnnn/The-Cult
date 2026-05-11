# VMaNGOS Client Data

This repo is the tracked home for the modified 1.12.1 client data used by the
Uranussaur / VMaNGOS setup.

Keep the following here:

- client-side patch files
- any custom MPQ or data diffs
- notes for rebuilding the client after server updates

Do not keep transient cache files here:

- `WDB/`
- logs
- temp crash dumps

The goal is to make client updates repeatable instead of redoing them manually
from screenshots and memory.

## Build a player patch bundle

Use `package_client_patch_bundle.py` to create a minimal release for players.
It rebuilds one `patch-Z.MPQ` from the active patched DBC/model/texture files in
`..\vmangos-dbc-inspect`, then writes a versioned bundle under
`patches\releases\`.

```powershell
python .\package_client_patch_bundle.py --label one-file-installer --publish-current
```

This refreshes the stable repo payload:

- `patch-Z.MPQ`
- `manifest.json`
- `required-files.tsv`

It also writes the root `WowCult.bat`. Players only need that one script. It
fetches the current launcher from the repo, verifies and installs the current
MPQ into the detected WoW `Data` folder, refreshes addons, sets the realm config,
creates the ongoing launcher inside the WoW folder, and starts the game.

Player download URL after pushing `master`:

```text
https://raw.githubusercontent.com/fogennnnn/The-Cult/master/WowCult.bat
```

`WowCult.bat` is both installer and launcher. First run asks for the WoW folder
if auto-detect fails, asks for account/password if no saved login exists, writes
`WowCult.bat` into the WoW folder, creates shortcuts with the `WoW.exe` icon, and
launches. Later runs use the same script to update/check patch files and launch.

Optional account-name prefill:

```powershell
.\WowCult.bat -AccountName "myaccount"
```

This writes only `SET accountName` to `WTF\Config.wtf`. It does not store a
password.

Optional saved login setup:

```powershell
.\WowCult.bat -SetupLogin
```

The launcher stores the password with Windows user encryption under
`%LOCALAPPDATA%\TheCult`, uses Windows Hello once per boot when available, then
launches WoW and submits the saved password quickly. If a client does not focus the
password field after `SET accountName`, launch with `-TypeAccountOnLogin` once.

Setup mode also writes `WowCult.bat` into the WoW client folder and creates
shortcuts with the `WoW.exe` icon on the desktop, in the Start menu, and in the
current user's taskbar pinned-shortcut folder. Modern Windows may still require
the user to approve/refresh the actual taskbar pin, but the shortcut file is
created in the standard pinned location.

To patch without being prompted for login setup:

```powershell
.\WowCult.bat -NoLoginSetup
```

Forget the saved login:

```powershell
.\WowCult.bat -ForgetLogin
```
