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

# Vehicle spawn regression (operator 2026-07-20: 5 clamp clicks nested 5 hulls
# into a sky-ladder that read as "spawning is unsuccessful"). Boots its own
# MainWorld: clearance gate must refuse nested clicks, the single clamp must
# rest on the ground. ~2 min.
echo "== vehicle spawn (clamp nesting) =="
"$GODOT" --headless --path "$PROJ" \
	res://src/tests/repro_clamp_spawn.tscn > "$OUT/clamp_spawn.log" 2>&1
grep -E "ok    |FAIL  |Result:" "$OUT/clamp_spawn.log" || true
# Key off the printed verdict, not the exit code: Godot occasionally segfaults
# in engine teardown AFTER a clean PASS (observed exit 139 with all checks ok).
if ! grep -q "Result: PASS" "$OUT/clamp_spawn.log"; then
	echo "FAIL  : clamp spawn regression (see $OUT/clamp_spawn.log)"
	[ $code -eq 0 ] && code=1
fi

# Fixes proven this session — each asserts the exact defect the operator hit, so
# none of them can silently rot: map frame (player inside the shell renders
# inside the drawn outline), nested-hull drift (parked vehicles do not travel),
# NPC waypoint guard, feeder fetches its kit on foot instead of conjuring it.
for t in test_map_frame test_nested_vehicle_drift test_npc_target_guard test_feeder_fetch; do
	echo "== $t =="
	"$GODOT" --headless --path "$PROJ" "res://src/tests/$t.tscn" > "$OUT/$t.log" 2>&1
	grep -E "^  (ok|FAIL)|Result|RESULT" "$OUT/$t.log" || true
	# Key off the printed verdict, not the exit code: Godot can segfault in
	# teardown after a clean PASS (observed exit 139 with every check ok).
	if ! grep -qE "Result: PASS|RESULT: PASS" "$OUT/$t.log"; then
		echo "FAIL  : $t (see $OUT/$t.log)"
		[ $code -eq 0 ] && code=1
	fi
done

echo "== done (exit $code) — see $OUT/topdown.png =="
exit $code
