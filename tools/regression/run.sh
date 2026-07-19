#!/usr/bin/env bash
# One-command world/save regression for CeDo Simulator.
#
# Boots the REAL MainWorld headless against the REAL world_layout.json and:
#   - asserts world creation (Plant init, floor grade, shell, doors on walls);
#   - validates every operator line macro is not corrupt (insane deltas);
#   - builds line_3a from the clean seed and asserts EVERY machine lands
#     inside the building, then save->reload round-trips to <1 cm;
#   - renders a top-down verification PNG (green = inside, red = outside).
#
# Exit code 0 = all green. Non-zero = a check failed (see the log / PNG).
#
# Usage:   bash tools/regression/run.sh
# Override the engine path with:  GODOT=/path/to/godot bash tools/regression/run.sh
set -uo pipefail

GODOT="${GODOT:-C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe}"
PROJ="C:/Users/arnod/Documents/CeDo_Simulator"
UD="C:/Users/arnod/AppData/Roaming/Godot/app_userdata/CeDo Simulator"
OUT="$PROJ/tools/regression/out"
mkdir -p "$OUT"

echo "== importing =="
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1

# Warnings are errors here, but there is NO headless way to see GDScript
# warnings (--check-only, runtime load(), and --headless --editor --quit all
# print nothing — verified on 4.6.3). They only reach the operator in the
# editor. This static check covers the one that keeps shipping.
echo "== unused-parameter lint =="
if ! python3 "$PROJ/tools/regression/lint_unused_params.py" "$PROJ/src"; then
	echo "FAIL  : unused parameter(s) — would warn in the editor"
	exit 1
fi

echo "== running regression =="
"$GODOT" --headless --path "$PROJ" \
	--main-scene res://src/tests/regression_world_save.tscn > "$OUT/last_run.log" 2>&1
code=$?
grep -E "^\[|ok    :|FAIL  :|note  :|skip  :|Result:" "$OUT/last_run.log" || true

echo "== rendering top-down =="
cp "$UD/regression_positions.json" "$OUT/positions.json" 2>/dev/null || true
python3 "$PROJ/tools/regression/topdown_render.py" "$OUT/positions.json" "$OUT/topdown.png" || true

echo "== done (exit $code) — see $OUT/topdown.png =="
exit $code
