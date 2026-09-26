# `tools/drive_sync/` — one-click mirror of the checkout to Google Drive

`CeDoDriveSync.ps1` puts a **CeDo - Sync to Drive** button on the operator's desktop. One click
mirrors `%USERPROFILE%\Documents\CeDo_Simulator` to
`My Drive/Priority Docs/CeDo Simulator/CeDo_Simulator` with a pinned rclone (v1.75.1): tracked
files, `assets/`, `.godot/` and every other gitignored file. Only `.git` folders are left out
(GitHub has them). It runs when clicked, never on its own.

Why: `assets/` and `.godot/` are in git nowhere, and `assets/` was wiped on 2026-09-21
(`docs/audit/assets_loss_and_restore_2026-09-21.md`).

## Install (Windows, PowerShell 7, once)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\Documents\CeDo_Simulator\tools\drive_sync\CeDoDriveSync.ps1" -Install
```

The installer:
- copies the script to `%LOCALAPPDATA%\CeDoDriveSync\`. The button runs that copy, so a branch
  switch never changes it. Re-run `-Install` after pulling a newer version; `config.json`
  settings are kept.
- downloads rclone v1.75.1 and checks its SHA-256 against the value pinned in the script.
- reuses a Drive remote from the existing `rclone.conf` if one can open and write the target
  folder. Otherwise it creates `cedo-gdrive`, which means one Google login in the browser.
- creates the Drive folders `CeDo_Simulator` and `CeDo_Simulator_versions`, then the shortcut.

## What a click does

| step | behaviour |
|---|---|
| compare | `rclone sync --checksum`: size + MD5 of every file against the MD5 Drive stores |
| upload | new and changed files only; a renamed file is moved on Drive, not uploaded again |
| delete, overwrite | the old copy moves to `CeDo_Simulator_versions/<run stamp>/` first; stamps older than 30 days go to the Drive trash |
| links | junctions and symlinks are listed on screen and skipped (rclone never follows them) |

Checks that run before anything changes on Drive:
- `project.godot` must say `config/name="CeDo Simulator"`, so a wrong or emptied folder syncs nothing.
- **Shrink guard.** A top-level folder that had at least 20 files at the last good sync and has
  lost at least 50 % of them stops the run until you type `YES`. It prints the restore command.
- **Delete limit.** More than 100 deletions stop rclone (`--max-delete`) until you type `YES`.
- One sync at a time (a named mutex). The PC doesn't sleep while a run is going.
- On the first run, a Drive quota check.

The first run uploads everything. Drive creates about 2 files/s (rclone docs, "Limitations"),
and the script prints the resulting estimate. Closing the window stops the run; the next click
continues where it left off.

## Restore

The shrink guard prints this command already filled in. To run it by hand:

```powershell
$c = Get-Content "$env:LOCALAPPDATA\CeDoDriveSync\config.json" -Raw | ConvertFrom-Json
$folder = 'assets'   # the top-level folder to bring back
& $c.RcloneExe copy "$($c.Remote),root_folder_id=$($c.DriveFolderId):$($c.MirrorFolder)/$folder" (Join-Path $c.LocalPath $folder) --checksum -P --config $c.RcloneConfigPath
```

For an older version of a file, list the run stamps with
`& $c.RcloneExe lsf "$($c.Remote),root_folder_id=$($c.DriveFolderId):$($c.VersionsFolder)" --dirs-only --config $c.RcloneConfigPath`,
then copy from `$($c.VersionsFolder)/<stamp>/<path>` the same way.

## Settings and switches

`%LOCALAPPDATA%\CeDoDriveSync\config.json`:

| key | default | meaning |
|---|---|---|
| `Mode` | `mirror` | `add-only` never deletes anything on Drive |
| `MaxDeletePerRun` | 100 | the delete limit above |
| `ShrinkGuardMinFiles`, `ShrinkGuardMaxLossRatio` | 20, 0.5 | the shrink guard above |
| `VersionsKeepDays` | 30 | 0 keeps every version folder |
| `ExcludeGitDirs` | `true` | skip every `.git` folder |
| `LogsKeep` | 60 | newest JSON logs kept in `logs\` |

Switches:
- `-DryRun` shows what a run would change and changes nothing.
- `-AllowMassDelete` lifts both guards for one run.
- `-NoPause` is for scheduled use; it never asks and never confirms.
- `-Uninstall` removes the shortcut and the install folder.
- `-Install` also accepts `-LocalPath`, `-DriveFolderId`, `-RemoteName`, `-RcloneConfigPath` and `-Hotkey`.

The Drive folder ID is in the script, and this repo is public. On 2026-09-26 that folder and
its parent were owner-only (Drive API permissions), so the ID gives nobody access. If the
folder is ever shared by link, the ID in this file becomes that link.

## Tests

```bash
bash tools/drive_sync/test/run_tests.sh
```

Linux x86_64 only (a Claude cloud session is enough). It downloads rclone v1.75.1 and
PowerShell 7.4.6, checks both against their published SHA-256, and replaces Drive with an rclone
`local` remote. The script's `<remote>,root_folder_id=<id>:<path>` spec works on that remote
unchanged.

Measured 2026-09-26: **91 passed, 0 failed, 0 skipped**, in 16 scenarios. Twice in a row, and
once from a cold download cache (59 s). The suite covers:
- first run, a no-change run, and an edit with the same size and nanosecond mtime that only MD5
  can see;
- rename, delete, the versions folder, the shrink guard and the restore it prints, the delete
  limit, pruning old stamps;
- dry run, identity check, the lock, add-only mode;
- a real console (pty) with live progress;
- the installer's download, SHA-256 check, config discovery and remote selection.

Each mutation below turns the suite red:

| mutation | checks red |
|---|---|
| drop `--checksum` | 4 |
| disable the shrink guard | 14 |
| drop `--max-delete` | 4 |
| run rclone through `&` instead of a console child (its progress then lands in the return value and a good run reads FAILED, a real bug found this way) | 2 |
| skip the SHA-256 check | 2 |

Not covered, because it is Windows-only: the desktop shortcut, the sleep block, the Google
login, and the real Drive API. The first run on the operator's PC is the test for those.
