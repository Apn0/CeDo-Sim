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
raw_code=$?
grep -E "^\[|ok    :|FAIL  :|note  :|skip  :|Result:" "$OUT/last_run.log" || true

# Verdict-based, like every step below: Godot can segfault in TEARDOWN after a
# clean pass (observed exit 139 with "15 ok, 0 fail" already printed). Keying the
# whole harness off the process exit code turns that into a false red, and a
# harness that randomly reports red teaches you to ignore it — the mirror of the
# vacuous greens that let the map/npc-05 bugs survive. So: trust the printed
# verdict, and report a post-verdict crash as a NOTE rather than a failure.
code=0
if grep -qE "^Result: [0-9]+ ok, 0 fail" "$OUT/last_run.log"; then
	if [ $raw_code -ne 0 ]; then
		echo "note  : regression passed but the engine exited $raw_code (teardown crash, not a test failure)"
	fi
else
	echo "FAIL  : regression verdict missing or non-zero fail count (see $OUT/last_run.log)"
	code=1
fi

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
#
# test_vehicle_spawn_frame: markers are SCENE-ABSOLUTE; _layout_to_scene used to
# rotate+anchor them, spawning every vehicle ~228 m from where the operator drew
# it. Mutation-tested — reverting that function turns 4 of its checks red. Note
# the regression's own "within 500 m of plant" check stayed GREEN throughout the
# bug, which is exactly why an identity assertion had to exist.
# test_jam_baseline reproduces the two measured wedge coordinates deterministically.
# Its ARRIVAL checks print BLOCKED rather than FAIL while the building models no
# doorways (world_layout structure_items is empty, so the router honestly returns
# a 0-point route across the facade) — the wedge checks stay hard, and arrival
# goes hard automatically once a gate is placed. Grep the logs for 'BLOCKED:' to
# see what the missing door survey is still costing.
# npc-06/07 navigation: test_nav_connectivity proves the carved navmesh did NOT
# seal the plant (crew still route post<->canteen both ways); test_outdoor_route
# proves a vehicle drives a 205 m apron-to-apron leg around the building instead
# of dead-reckoning into it. Both mutation-tested (reverting the pilot / the
# shell-bake flag turns them red).
# test_tag_snapshot: makes the operator's REAL 1056-tag SCADA export
# (src/data/plant/line3c_scada_tags.json) live for the first time via
# src/sim/TagMap.gd, and MEASURES two defects rather than asserting them:
#   (b) duplicate_id_collisions == 14 -- LineFlow._find_node_by_id returns the
#       FIRST match on a non-unique placeable id, so 14 of 47 machines are
#       unreachable by any front-end. THIS CRITERION INVERTS once machines get
#       unique keys: a genuine fix makes it 0, and this line must then be
#       REWRITTEN, not silenced.
#   (c) l3c_code is stamped on 0 of 47 nodes and sum(amps_nominal) == 0.00 A,
#       so the calibrated amps path is dead and the '~488 A' comment at
#       LineFlow.gd:1729-1730 is not what the sim reports. live_line_amps is
#       deliberately NOT fixtured -- it is not run-stable once the line is fed.
# Mutation-proven: empty map -> 7 fail, stubbed get_machine_info -> 6 fail,
# all-default values -> 3 fail, feed disabled -> 2 fail.
# test_waslijn3c_overzicht: the FIRST ported operator HMI screen (Waslijn 3C
# Overzicht -> WashingScope, which previously showed construction-time literals
# from an AI-enhanced photo and whose bind() had zero callers). Asserts the
# screen is HONEST: every field is either bound to real sim state through
# TagMap x LineFlow.get_machine_info(), or rendered '--'; no invented values.
# Mutation-proven, and the mutation is the point: M2 feeds structurally-perfect
# DEAD values and the bound/unavailable accounting stays exactly intact, so the
# accounting criterion alone would have passed it -- only the LIVENESS criterion
# catches it. That is the npc-05 shape. Do not weaken criterion E.
# It also reports (not asserts away) that L3C.14L renders 0 A while AAN, because
# l3c_code is stamped on 0 of 47 nodes -- fixing that stamping is what makes
# those currents real.
# test_gate_carve: single-click door/gate/window placement now carves its wall
# opening THE SAME FRAME (was reload-only). Its passability sample is reported,
# not gated — it caught a SEPARATE, unfixed WallOpenings limitation (giant
# procedural wall triangles + a thick double-sided shell defeat the 5 cm
# coplanarity test) that a same-day attempt to fix regressed test_door_carve.gd
# on; see the file header before touching WallOpenings._clip_triangle_against_box.
for t in test_map_frame test_nested_vehicle_drift test_npc_target_guard test_feeder_fetch test_vehicle_spawn_frame test_nav_connectivity test_outdoor_route test_jam_baseline test_gate_carve test_tag_snapshot test_waslijn3c_overzicht; do
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

# Spawn clearance. The 9334310 marker-frame fix moved 9 vehicles 120-270 m and
# 7 bale yards 290-355 m ONTO the plant. test_vehicle_spawn_frame proves they
# land ON their markers; NOTHING proved they land in FREE SPACE. This measures
# real shape overlap (vehicle's own hull, own transform) against every body in
# the space, plus a down-ray so nothing floats or is buried.
#
# TWO configurations, both gating, because they answer different questions:
#   NOLINE = the operator's real save alone. Authoritative for "what happens on
#            his next boot". Run FIRST because the populated run perturbs the
#            hulls under test — the synthetic line lifts MastLift onto a machine
#            and thereby HIDES the mast-lift nesting this configuration finds.
#   default = same world PLUS line_3a built from the clean seed, so hulls are
#            tested against a real machine line instead of a near-empty shell.
#
# Mutation-tested: SPAWNCLEAR_PLANT=1 embeds a hull in a static shipped machine
# and reproducibly reads 100 % penetration, turning 3 checks red.
# "ADVIS" lines are measured defects the file is deliberately not the gate for
# (see _advise in the test); they print in full and do not affect the verdict.
for cfg in "NOLINE" "LINE"; do
	echo "== spawn clearance ($cfg) =="
	if [ "$cfg" = "NOLINE" ]; then
		SPAWNCLEAR_NOLINE=1 "$GODOT" --headless --path "$PROJ" \
			"res://src/tests/test_spawn_clearance.tscn" > "$OUT/spawn_clearance_$cfg.log" 2>&1
	else
		"$GODOT" --headless --path "$PROJ" \
			"res://src/tests/test_spawn_clearance.tscn" > "$OUT/spawn_clearance_$cfg.log" 2>&1
	fi
	grep -aE "^  (ok|FAIL|ADVIS)  |^Result" "$OUT/spawn_clearance_$cfg.log" || true
	# Verdict-based, like every step above: Godot segfaults in teardown after a
	# clean pass on this one (observed with "0 fail" already printed).
	if ! grep -qaE "^Result: PASS" "$OUT/spawn_clearance_$cfg.log"; then
		echo "FAIL  : spawn clearance $cfg (see $OUT/spawn_clearance_$cfg.log)"
		[ $code -eq 0 ] && code=1
	fi
done

# npc-05 container chain. Bench is mutation-tested (reverting any single fix
# turns specific greens red). It was previously 31/31 green while the chain was
# DEAD in a real session, which is why the real-MainWorld variant exists and why
# the bench must never be trusted alone.
echo "== npc-05 container chain (bench) =="
"$GODOT" --headless --path "$PROJ" 	--script res://src/tests/test_npc05_container_chain.gd > "$OUT/npc05_bench.log" 2>&1
grep -E "^  FAIL|npc-05 container chain" "$OUT/npc05_bench.log" || true
if ! grep -q "npc-05 container chain PASS" "$OUT/npc05_bench.log"; then
	echo "FAIL  : npc-05 bench (see $OUT/npc05_bench.log)"
	[ $code -eq 0 ] && code=1
fi

# The regression net for WallOpenings' carve algorithm itself (visible-teeth
# check) — was never wired into the harness at all despite existing since
# before this session. Its whole job is to catch exactly the kind of
# regression a careless carve-algorithm change (attempted and reverted this
# session, see test_gate_carve.gd's header) would cause.
echo "== door carve (visible-teeth regression) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_door_carve.gd > "$OUT/door_carve.log" 2>&1
grep -E "boundary edges|teeth|PASS —|FAIL —|RESULT FAIL" "$OUT/door_carve.log" || true
if ! grep -q "PASS —" "$OUT/door_carve.log"; then
	echo "FAIL  : door carve (see $OUT/door_carve.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== done (exit $code) — see $OUT/topdown.png =="
exit $code
