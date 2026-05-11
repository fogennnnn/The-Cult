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

It also writes a root `install-client-patch.bat`. Players only need to
download that one script; it fetches the current MPQ from the repo, verifies the
hash, and installs it into the detected WoW `Data` folder.

Player download URL after pushing `master`:

```text
https://raw.githubusercontent.com/fogennnnn/The-Cult/master/install-client-patch.bat
```

Daily launcher URL:

```text
https://raw.githubusercontent.com/fogennnnn/The-Cult/master/Play-TheCult.bat
```

`Play-TheCult.bat` is the preferred shortcut for players. It refreshes the
launcher script, checks `patches/current/manifest.json`, installs `patch-Z.MPQ`
only when the remote hash changes, refreshes the bundled addons, clears WDB
after patch changes, repairs `realmlist.wtf`/`Config.wtf`, and starts `WoW.exe`.

Optional account-name prefill:

```powershell
.\Play-TheCult.bat -AccountName "myaccount"
```

This writes only `SET accountName` to `WTF\Config.wtf`. It does not store a
password.
