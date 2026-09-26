#!/usr/bin/env bash
# Tests for tools/drive_sync/CeDoDriveSync.ps1, on Linux (a Claude cloud session is enough).
#
# Google Drive is stood in for by an rclone `local` remote. The script's target spec
# `<remote>,root_folder_id=<id>:<path>` works on it unchanged (the local backend ignores
# root_folder_id and resolves <path> against the working directory, the fake Drive folder), so
# everything except Google itself runs for real: sync --checksum, --backup-dir, --track-renames,
# --max-delete, the guards, the summary, the console path in a pty, and the installer's
# download, SHA-256 check, config discovery and remote selection (install_checks.ps1).
# Not covered (Windows-only): the desktop shortcut, the sleep block, the Google login.
#
#   bash tools/drive_sync/test/run_tests.sh     exit 0 = every check passed and none skipped
#
# Downloads, cached in ~/.cache/cedo_drive_sync_test: rclone v1.75.1 and PowerShell 7.4.6 for
# Linux x86_64, each checked against the SHA-256 its project publishes.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/.." && pwd)/CeDoDriveSync.ps1"
[ -f "$SCRIPT" ] || { echo "not found: $SCRIPT"; exit 2; }
[ "$(uname -s)-$(uname -m)" = "Linux-x86_64" ] || { echo "needs Linux x86_64 (the pinned test binaries)"; exit 2; }
for t in curl sha256sum unzip tar find grep sed; do
    command -v "$t" >/dev/null || { echo "missing tool: $t"; exit 2; }
done

# From https://downloads.rclone.org/v1.75.1/SHA256SUMS and
# https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/hashes.sha256, fetched 2026-09-26.
RCLONE_URL=https://downloads.rclone.org/v1.75.1/rclone-v1.75.1-linux-amd64.zip
RCLONE_SHA=982b5aa772841168f8e380f139e9e787b2a105403e32b94da8676a0e1c0a13ab
PWSH_URL=https://github.com/PowerShell/PowerShell/releases/download/v7.4.6/powershell-7.4.6-linux-x64.tar.gz
PWSH_SHA=6f6015203c47806c5cc444c19d8ed019695e610fbd948154264bf9ca8e157561

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/cedo_drive_sync_test"
mkdir -p "$CACHE"
fetch() {  # url sha256 dest
    if [ -f "$3" ] && echo "$2  $3" | sha256sum -c --status; then return 0; fi
    curl -sSfL --retry 3 -o "${3:?}.part" "$1" || { echo "download failed: $1"; exit 2; }
    if ! echo "$2  $3.part" | sha256sum -c --status; then
        echo "SHA-256 mismatch: $1"; rm -f "${3:?}.part"; exit 2
    fi
    mv "$3.part" "$3"
}
fetch "$RCLONE_URL" "$RCLONE_SHA" "$CACHE/rclone.zip"
fetch "$PWSH_URL" "$PWSH_SHA" "$CACHE/pwsh.tgz"
RC="$CACHE/rclone-v1.75.1-linux-amd64/rclone"
[ -x "$RC" ] || { unzip -oq "$CACHE/rclone.zip" -d "$CACHE" && chmod 755 "$RC"; }
PW="$CACHE/pwsh-7.4.6/pwsh"
[ -x "$PW" ] || { mkdir -p "$CACHE/pwsh-7.4.6" && tar xzf "$CACHE/pwsh.tgz" -C "$CACHE/pwsh-7.4.6" && chmod 755 "$PW"; }
# No pipes into head/grep -q under pipefail: an early reader exit SIGPIPEs the writer, a random red.
ver="$("$RC" version)"; [ "${ver%%$'\n'*}" = "rclone v1.75.1" ] || { echo "rclone at $RC is not v1.75.1"; exit 2; }

E="$(mktemp -d "${TMPDIR:-/tmp}/cedo_drive_sync_test.XXXXXX")"
P="$E/proj/CeDo_Simulator"     # the project
D="$E/drive/CeDo_Simulator"    # the mirror on "Drive"
V="$E/drive/CeDo_Simulator_versions"
APP="$E/app"                   # stands in for %LOCALAPPDATA%\CeDoDriveSync

# ---- fixture ----------------------------------------------------------------------------------
mkdir -p "$E/drive" "$APP" "$P"/{assets/tex,assets/audio,.godot/imported,src/scripts,docs,.git/objects,addons/foo/.git,emptydir}
printf 'config_version=5\n\n[application]\n\nconfig/name="CeDo Simulator"\n' > "$P/project.godot"
for i in $(seq 1 30); do printf 'tex%02d-aaaa' "$i" > "$P/assets/tex/t$i.png"; done
for i in $(seq 1 25); do printf 'imp%02d' "$i" > "$P/.godot/imported/i$i.ctex"; done
for i in $(seq 1 40); do printf 'extends Node # %02d\n' "$i" > "$P/src/scripts/s$i.gd"; done
for i in $(seq 1 5); do echo "doc $i" > "$P/docs/d$i.md"; done
for i in $(seq 1 10); do echo "obj $i" > "$P/.git/objects/o$i"; done
echo "ref: refs/heads/main" > "$P/addons/foo/.git/HEAD"; echo "plugin" > "$P/addons/foo/plugin.cfg"
echo "root readme" > "$P/README.md"; head -c 3000000 /dev/urandom > "$P/assets/audio/big.wav"
ln -s /etc "$P/linkdir"
cp "$SCRIPT" "$APP/CeDoDriveSync.ps1"
printf '[gdrive]\ntype = local\n' > "$APP/rclone.conf"
cat > "$APP/config.json" <<JSON
{
  "SchemaVersion": 1,
  "LocalPath": "$P",
  "RcloneExe": "$RC",
  "RcloneConfigPath": "$APP/rclone.conf",
  "Remote": "gdrive",
  "DriveFolderId": "1DppntIc3JkDG_-1ExXGTnboueba9xtOZ",
  "DriveFolderLabel": "My Drive/Priority Docs/CeDo Simulator",
  "MirrorFolder": "CeDo_Simulator",
  "VersionsFolder": "CeDo_Simulator_versions",
  "Mode": "mirror",
  "ExcludeGitDirs": true,
  "MaxDeletePerRun": 5,
  "ShrinkGuardMinFiles": 20,
  "ShrinkGuardMaxLossRatio": 0.5,
  "VersionsKeepDays": 30,
  "LogsKeep": 60
}
JSON

# ---- helpers ----------------------------------------------------------------------------------
pass=0; fail=0; skip=0; out=''; rc=0
check() {  # name, then a command that succeeds when the check holds
    local name="$1"; shift
    if "$@"; then pass=$((pass + 1)); echo "  PASS $name"
    else
        fail=$((fail + 1)); echo "  FAIL $name"
        printf '%s\n' "$out" | tail -n 25 | sed 's/^/        | /'
    fi
}
run() { out="$(cd "$E/drive" && "$PW" -NoLogo -NoProfile -File "$APP/CeDoDriveSync.ps1" "$@" 2>&1)"; rc=$?; }
run_answering() { local answer="$1"; shift
    out="$(cd "$E/drive" && printf '%s\n' "$answer" | "$PW" -NoLogo -NoProfile -File "$APP/CeDoDriveSync.ps1" "$@" 2>&1)"; rc=$?; }
has() { grep -qE -- "$1" <<< "$out"; }
has_text() { grep -qF -- "$1" <<< "$out"; }
lacks_text() { ! has_text "$1"; }
files_in() { find "$1" -type f 2>/dev/null | wc -l; }
is() { [ "$1" -eq "$2" ]; }
same() { [ "$1" = "$2" ]; }
exists() { [ -e "$1" ]; }
missing() { [ ! -e "$1" ]; }
glob_content() { local f; for f in $1; do [ -f "$f" ] && [ "$(cat "$f")" = "$2" ] && return 0; done; return 1; }

# ---- scenarios --------------------------------------------------------------------------------
echo "### 1 first run"
run -NoPause
check "exit 0" is "$rc" 0
check "104 files on the mirror" is "$(files_in "$D")" 104
check "no .git anywhere on Drive (root and nested)" same "$(find "$E/drive" -name .git)" ""
check "empty dir mirrored" exists "$D/emptydir"
check "link reported and skipped" has_text "Link NOT uploaded (rclone skips links): linkdir"
check "state.json written" exists "$APP/state.json"
check "folder table printed" has '^assets +31 '

echo "### 2 no-change run"
run -NoPause
check "exit 0" is "$rc" 0
check "0 uploaded" has 'Uploaded \(new \+ changed\) +0 files'
check "104 compared by size + MD5" has 'Compared with Drive \(size \+ MD5\) +104 files'
check "no versions folder yet" missing "$V"

echo "### 3 same-size same-mtime edit, add, delete x2, rename"
touch -r "$P/assets/tex/t1.png" "$E/t1.mtime"    # exact mtime, nanoseconds included
printf 'tex01-bbbb' > "$P/assets/tex/t1.png"; touch -r "$E/t1.mtime" "$P/assets/tex/t1.png"
check "fixture: edited t1 has the mirror copy's size and mtime (only MD5 differs)" \
    same "$(stat -c '%s %y' "$P/assets/tex/t1.png")" "$(stat -c '%s %y' "$D/assets/tex/t1.png")"
echo "new file" > "$P/docs/new.md"; rm "$P/src/scripts/s1.gd" "$P/src/scripts/s2.gd"; mv "$P/docs/d1.md" "$P/docs/d1_renamed.md"
run -NoPause
check "exit 0" is "$rc" 0
check "change seen by MD5 alone is uploaded" same "$(cat "$D/assets/tex/t1.png")" "tex01-bbbb"
check "old t1 kept in the versions folder" glob_content "$V/*/assets/tex/t1.png" "tex01-aaaa"
check "deleted s1 gone from the mirror" missing "$D/src/scripts/s1.gd"
check "deleted s1 kept in the versions folder" glob_content "$V/*/src/scripts/s1.gd" "extends Node # 01"
check "rename done on Drive" exists "$D/docs/d1_renamed.md"
check "old name gone" missing "$D/docs/d1.md"
check "summary: 1 rename" has 'Renamed on Drive \(no re-upload\) +1$'
check "summary: 2 uploads" has 'Uploaded \(new \+ changed\) +2 files'
check "summary: 1 changed + 2 deleted archived" has_text "1 changed + 2 deleted"

echo "### 4 assets/ wiped: the shrink guard stops an unattended run"
rm -f -- "${P:?}/assets/tex/"*.png
run -NoPause
check "exit 1" is "$rc" 1
check "last good sync shown as ISO 8601" has 'last good sync \(20[0-9]{2}-[0-9]{2}-[0-9]{2}T'
check "guard names assets 31 -> 1" has '^assets +31 +1 +97%'
check "restore command printed" has_text "copy 'gdrive,root_folder_id=1DppntIc3JkDG_-1ExXGTnboueba9xtOZ:CeDo_Simulator/assets'"
check "mirror untouched" is "$(files_in "$D/assets/tex")" 30

echo "### 5 shrink guard, answered 'no'"
run_answering no
check "exit 1, stopped" has_text "Stopped by the shrink guard"
check "mirror untouched" is "$(files_in "$D/assets/tex")" 30

echo "### 6 restore with the printed command, then sync"
restore="$(printf '%s\n' "$out" | grep -o "copy 'gdrive[^\"]*" | head -1)"
(cd "$E/drive" && eval "\"\$RC\" $restore" >/dev/null 2>&1); rc=$?
check "restore exit 0" is "$rc" 0
check "30 textures back locally" is "$(files_in "$P/assets/tex")" 30
run -NoPause
check "next sync exit 0" is "$rc" 0
check "next sync uploads nothing" has 'Uploaded \(new \+ changed\) +0 files'

echo "### 7 eight deletions against MaxDeletePerRun 5"
for i in $(seq 3 10); do rm "$P/src/scripts/s$i.gd"; done
run -NoPause
check "exit 7" is "$rc" 7
check "delete limit reported" has_text "DELETE LIMIT"
check "only 5 removed from the mirror" is "$(files_in "$D/src/scripts")" 33
out="$(cat "$APP/state.json")"; check "state.json not advanced (still 103 files)" has_text '"TotalFiles": 103'
run_answering YES
check "YES finishes: exit 0" is "$rc" 0
check "mirror now at 30 scripts" is "$(files_in "$D/src/scripts")" 30

echo "### 8 version folders past VersionsKeepDays"
mkdir -p "$V/20250101T000000+0100/x" && echo old > "$V/20250101T000000+0100/x/f.txt"
mkdir -p "$V/not-a-stamp" && echo keep > "$V/not-a-stamp/k.txt"
echo "touch" >> "$P/README.md"
run -NoPause
check "exit 0" is "$rc" 0
check "the 2025 stamp purged" missing "$V/20250101T000000+0100"
check "a folder that is not a stamp is left alone" exists "$V/not-a-stamp/k.txt"
check "recent stamps kept" [ "$(find "$V" -mindepth 1 -maxdepth 1 -name '2026*' | wc -l)" -ge 2 ]

echo "### 9 dry run"
echo "dry change" >> "$P/docs/d2.md"; before="$(cat "$D/docs/d2.md")"; state_before="$(md5sum < "$APP/state.json")"
run -NoPause -DryRun
check "exit 0" is "$rc" 0
check "Drive unchanged" same "$(cat "$D/docs/d2.md")" "$before"
check "state.json unchanged" same "$(md5sum < "$APP/state.json")" "$state_before"
check "preview: would upload 1" has 'Would upload \(new \+ changed\) +1 files'
check "preview: would archive 1 changed" has_text "1 changed + 0 deleted"

echo "### 10 identity check"
mv "$P/project.godot" "$P/project.godot.x"; run -NoPause; mv "$P/project.godot.x" "$P/project.godot"
check "no project.godot: exit 1" is "$rc" 1
check "no project.godot: says so" has_text "No project.godot"
sed -i 's/CeDo Simulator/Other Game/' "$P/project.godot"; run -NoPause; sed -i 's/Other Game/CeDo Simulator/' "$P/project.godot"
check "wrong config/name: exit 1" is "$rc" 1
check "wrong config/name: says so" has_text 'config/name="Other Game"'

echo "### 11 one sync at a time"
"$PW" -NoLogo -NoProfile -Command '$m = [System.Threading.Mutex]::new($false, "Local\CeDoDriveSync"); [void]$m.WaitOne(0); Start-Sleep 8' &
holder=$!; sleep 3
run -NoPause
check "second instance refused: exit 1" is "$rc" 1
check "second instance refused: says so" has_text "already running"
wait "$holder"

echo "### 12 add-only mode keeps deletions on Drive"
sed -i 's/"Mode": "mirror"/"Mode": "add-only"/' "$APP/config.json"; rm "$P/docs/d3.md"
run -NoPause
sed -i 's/"Mode": "add-only"/"Mode": "mirror"/' "$APP/config.json"
check "exit 0" is "$rc" 0
check "d3 still on Drive" exists "$D/docs/d3.md"

echo "### 13 no config.json"
mv "$APP/config.json" "$APP/config.json.x"; run -NoPause; mv "$APP/config.json.x" "$APP/config.json"
check "exit 1" is "$rc" 1
check "tells how to install" has_text "Run the installer first"

echo "### 14 console run in a pty: live progress, exit code, pause prompt"
if command -v script >/dev/null && command -v stty >/dev/null; then
    head -c 40000000 /dev/urandom > "$P/assets/audio/big3.wav"
    (cd "$E/drive" && printf '\n' | script -qefc "stty cols 120 rows 40; '$PW' -NoLogo -NoProfile -File '$APP/CeDoDriveSync.ps1'" /dev/null > "$E/pty.out" 2>&1); rc=$?
    out="$(sed -E 's/\x1b\][^\x07]*\x07//g; s/\x1b\[[0-9;?]*[a-zA-Z]//g; s/\r/\n/g' "$E/pty.out")"
    check "exit 0 through the pty" is "$rc" 0
    check "rclone's progress reached the console" has_text "Transferred:"
    check "reported DONE" has '^DONE:'
    check "not reported FAILED" lacks_text "FAILED"
    check "pause prompt shown" has_text "Press Enter to close"
    check "big3 uploaded byte for byte" cmp -s "$P/assets/audio/big3.wav" "$D/assets/audio/big3.wav"
else
    skip=$((skip + 1)); echo "  SKIP (needs script(1) and stty)"
fi

echo "### 15 dry run during an assets/ wipe: warns, previews, changes nothing"
mv "$P/assets/tex" "$E/tex_hold"; mkdir -p "$P/assets/tex"; before="$(files_in "$D/assets/tex")"
run -NoPause -DryRun
rmdir "$P/assets/tex"; mv "$E/tex_hold" "$P/assets/tex"
check "exit 0" is "$rc" 0
check "alarm shown" has_text "SHRINK GUARD"
check "dry run continues past it" has_text "Dry run: continuing"
check "preview: 30 deletions" has_text "0 changed + 30 deleted"
check "Drive untouched" is "$(files_in "$D/assets/tex")" "$before"

echo "### 16 installer internals (install_checks.ps1)"
mkdir -p "$E/pathdir" "$E/cwd" "$E/home"
cp "$RC" "$E/pathdir/rclone"; printf '[existing]\ntype = local\n' > "$E/pathdir/rclone.conf"
printf '[bad]\ntype = alias\nremote = /nonexistent/cedo_drive_sync\n\n[good]\ntype = local\n\n[pref]\ntype = local\n' > "$E/sel.conf"
out="$(cd "$E/cwd" && env -u RCLONE_CONFIG -u XDG_CONFIG_HOME HOME="$E/home" PATH="$E/pathdir:/usr/bin:/bin" \
    "$PW" -NoLogo -NoProfile -File "$HERE/install_checks.ps1" -Script "$SCRIPT" -Work "$E" -RcloneSha "$RCLONE_SHA" 2>&1)"
printf '%s\n' "$out" | grep -E '^  (PASS|FAIL)'
ip="$(printf '%s\n' "$out" | sed -n 's/^RESULT: \([0-9]*\) passed, \([0-9]*\) failed$/\1/p')"
if [ -n "$ip" ]; then
    pass=$((pass + ip)); fail=$((fail + $(printf '%s\n' "$out" | sed -n 's/^RESULT: [0-9]* passed, \([0-9]*\) failed$/\1/p')))
else
    fail=$((fail + 1)); echo "  FAIL install_checks.ps1 printed no RESULT line"; printf '%s\n' "$out" | tail -n 25 | sed 's/^/        | /'
fi

echo
echo "RESULT: $pass passed, $fail failed, $skip skipped"
if [ "$fail" -eq 0 ] && [ "$skip" -eq 0 ]; then rm -rf "${E:?}"; exit 0; fi
echo "work dir kept for inspection: $E"
[ "$fail" -gt 0 ] && exit 1
exit 3
