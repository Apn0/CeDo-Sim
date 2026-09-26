#!/usr/bin/env bash
# Build the Steam package of CeDo Simulator (Windows 64-bit). See docs/steam/README.md.
#
#   bash tools/steam/build_windows.sh
#
# 1. copies the operator's world_layout.json into steam_seed/ (gitignored); an
#    exported build writes it to a player's user:// on first launch
#    (WorldLayout._seed_from_build). His real file is only read.
# 2. regenerates export_presets.cfg (tools/steam/gen_export_preset.py)
# 3. exports the release build into $OUT; a previous build there is moved aside
#    to $OUT.prev-<stamp>, never deleted
# 4. writes $OUT/../build_info-<stamp>.txt: commit, seed md5, file sizes
#
# Overrides: PROJ, GODOT, OUT, LAYOUT.
# The exported game shares its user:// with the editor (app_userdata/CeDo
# Simulator). To test a build, give it a scratch APPDATA; see the README.
set -euo pipefail

PROJ="${PROJ:-$(cd "$(dirname "$0")/../.." && pwd)}"
GODOT="${GODOT:-C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe}"
OUT="${OUT:-/d/cedo_archive/steam/build/windows}"
LAYOUT="${LAYOUT:-$(cygpath -u "$APPDATA")/Godot/app_userdata/CeDo Simulator/world_layout.json}"
STAMP="$(date +%Y%m%d-%H%M%S)"

cd "$PROJ"
echo "== project  $PROJ ($(git rev-parse --short HEAD)$(git diff --quiet HEAD -- || echo ', uncommitted changes'))"

echo "== seed     $LAYOUT"
python -c "import json,sys; d=json.load(open(sys.argv[1],encoding='utf-8')); assert isinstance(d,dict) and d, 'not a non-empty object'" "$LAYOUT"
mkdir -p steam_seed
cp "$LAYOUT" steam_seed/world_layout.json
SEED_MD5="$(md5sum steam_seed/world_layout.json | cut -d' ' -f1)"
echo "           md5 $SEED_MD5"

echo "== preset"
python tools/steam/gen_export_preset.py "$PROJ"

if [ -n "$(ls -A "$OUT" 2>/dev/null)" ]; then
	echo "== moving the previous build to $OUT.prev-$STAMP"
	mv "$OUT" "$OUT.prev-$STAMP"
fi
mkdir -p "$OUT"

LOG="$(dirname "$OUT")/export-$STAMP.log"
echo "== export   -> $OUT (log $LOG)"
set +e
timeout --kill-after=30 2400 "$GODOT" --headless --path "$PROJ" \
	--export-release "Windows Desktop" "$(cygpath -m "$OUT")/CeDoSimulator.exe" > "$LOG" 2>&1
RC=$?
set -e
for f in CeDoSimulator.exe CeDoSimulator.pck godot_wry.dll libgodot_rapier.windows.x86_64-pc-windows-msvc.dll; do
	[ -s "$OUT/$f" ] || { echo "FAIL: $OUT/$f missing after export (godot exit $RC, see $LOG)"; exit 1; }
done

INFO="$(dirname "$OUT")/build_info-$STAMP.txt"
{
	echo "built      $STAMP"
	echo "commit     $(git rev-parse HEAD)$(git diff --quiet HEAD -- || echo ' + uncommitted changes')"
	echo "seed md5   $SEED_MD5  ($LAYOUT)"
	echo "godot      $("$GODOT" --version 2>/dev/null | tr -d '\r')"
	echo "files:"
	(cd "$OUT" && ls -l)
} > "$INFO"
cat "$INFO"
echo "== done (godot exit $RC). Probe it before uploading: docs/steam/README.md, 'Checking a build'."
