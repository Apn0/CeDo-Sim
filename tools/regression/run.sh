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

# All three are overridable so the harness runs off-Windows (Linux CI, a cloud
# session) without editing this file. The defaults are the operator's Windows
# paths and are unchanged — plain `bash tools/regression/run.sh` on that machine
# behaves exactly as before.
GODOT="${GODOT:-C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe}"
PROJ="${PROJ:-C:/Users/arnod/Documents/CeDo_Simulator}"
UD="${UD:-C:/Users/arnod/AppData/Roaming/Godot/app_userdata/CeDo Simulator}"
OUT="$PROJ/tools/regression/out"
mkdir -p "$OUT"

echo "== importing =="
"$GODOT" --headless --path "$PROJ" --import >/dev/null 2>&1

# Warnings are errors here, but there is NO headless way to see GDScript
# warnings (--check-only, runtime load(), and --headless --editor --quit all
# print nothing — verified on 4.6.3). They only reach the operator in the
# editor. This static check covers the one that keeps shipping.
# PARSE GATE. The lint below only checks unused parameters — it has NO idea
# whether the project compiles. Measured 2026-07-29: a tree referencing an
# undeclared constant (S_FIRST_MATCH) passed the lint clean while the sim could
# not compile at all ("Parse Error ... Failed to compile depended scripts"), and
# every behavioural step after it would have been testing a corpse. A boot that
# prints no Parse/Compile Error is seconds of work and closes that gap.
echo "== parse gate =="
"$GODOT" --headless --path "$PROJ" --quit > "$OUT/parse_gate.log" 2>&1
if grep -qE "Parse Error|Compile Error" "$OUT/parse_gate.log"; then
	echo "FAIL  : the project does not compile —"
	grep -E "Parse Error|Compile Error" "$OUT/parse_gate.log" | sort -u | head -10
	exit 1
fi

echo "== unused-parameter lint =="
if ! python3 "$PROJ/tools/regression/lint_unused_params.py" "$PROJ/src"; then
	echo "FAIL  : unused parameter(s) — would warn in the editor"
	exit 1
fi

# HMI PALETTE CENSUS. src/scenes/hud/scopes/HmiScreenBase.gd holds ONE chrome
# palette for the whole "Waslijn 3C *" screen family; this fails if a screen in
# that family uses a shared colour the base does not declare, which would make
# every port of that screen render it wrong. It found #888 (the OFF-checkbox
# ring, on 13 of the 16 screens) missing on its first correct run.
echo "== hmi palette census =="
if ! python3 "$PROJ/tools/hmi/palette_census.py"; then
	echo "FAIL  : a shared HMI chrome colour is not declared in HmiScreenBase.gd"
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
# (src/data/plant/line3c_scada_tags.json) live via src/sim/TagMap.gd, resolved
# per L3C UNIT. Criteria (b) and (c) were REWRITTEN on 2026-07-29 -- as the old
# text below them demanded -- because both INVERTED when the addressing defect
# they measured was fixed. What they used to record:
#   (b) duplicate_id_collisions == 14. LineFlow could only be asked for a
#       PLACEABLE ID and returned the first match, so 14 of 47 machines were
#       unreachable by any front-end. LineFlow now mints a per-instance key, so
#       (b) asserts the thing that criterion was a proxy for: every machine has a
#       DISTINCT non-empty key AND get_machine_info(key) resolves to THAT node
#       (identity -- a resolver ignoring the key would still return a non-empty
#       dict, which is the vacuous version). The 14-collision census is KEPT and
#       still printed: duplicate ids are normal and harmless now that an id is a
#       machine TYPE rather than the only handle.
#   (c) l3c_code stamped on 0 of 47 nodes, sum(amps_nominal) == 0.00 A against
#       ProcessModel.line_nominal_amps() 488.49 A -- the calibrated amps path was
#       dead and every current in the sim came from MotorOverload's PLACEHOLDER
#       90 A default. (c) now asserts BOTH directions: the line_3c spine carries
#       all 32 codes and sums to exactly 488.49 A, AND no machine outside that
#       macro carries a 3C code (a Line 3A frictiescheider is not L3C.4L, and
#       stamping by id would also re-route 3A onto the Line3CDef.LINKS graph).
#       live_line_amps stays deliberately NOT fixtured -- not run-stable once fed.
# Mutation-proven: empty map -> 7 fail, stubbed get_machine_info -> 6 fail,
# all-default values -> 3 fail, feed disabled -> 2 fail.
# test_l3c_unit_screens: the per-unit L3C screens (L3C.14 dryer LINKS/RECHTS),
# one layout engine + verbatim spec data. Its criterion A re-reads the
# operator's own HTML export at run time and fails if a spec label was
# invented or a motor card silently dropped, so the screens cannot drift into
# plausible fiction. Criterion F is the headline: the two dryers are the same
# machine TYPE and both read 0.00 A before the l3c_code work, so their
# currents must now differ AND their ratio must match the two hand-transcribed
# nominals (70.80/63.51) — a shared nominal would force that ratio to 1.0.
# test_waslijn3c_overzicht: the FIRST ported operator HMI screen (Waslijn 3C
# Overzicht -> WashingScope, which previously showed construction-time literals
# from an AI-enhanced photo and whose bind() had zero callers). Asserts the
# screen is HONEST: every field is either bound to real sim state through
# TagMap x LineFlow.get_machine_info(), or rendered '--'; no invented values.
# Mutation-proven, and the mutation is the point: M2 feeds structurally-perfect
# DEAD values and the bound/unavailable accounting stays exactly intact, so the
# accounting criterion alone would have passed it -- only the LIVENESS criterion
# catches it. That is the npc-05 shape. Do not weaken criterion E.
# Its bound/unavailable split moved 13/25 -> 28/10 when the ten units that shared
# a placeable id with a mapped sibling became addressable by their own plant code.
# It now also builds line_3a ALONGSIDE line_3c as an adversarial decoy (same ids,
# different equipment) and adds criterion G: every bound field must resolve
# through a machine whose OWN l3c_code equals the caption -- the check the old
# first-match screen could not have passed.
# test_gate_carve: single-click door/gate/window placement now carves its wall
# opening THE SAME FRAME (was reload-only). Its passability sample is reported,
# not gated — it caught a SEPARATE, unfixed WallOpenings limitation (giant
# procedural wall triangles + a thick double-sided shell defeat the 5 cm
# coplanarity test) that a same-day attempt to fix regressed test_door_carve.gd
# on; see the file header before touching WallOpenings._clip_triangle_against_box.
# test_line3c_seq_alignment: pure-data guard, no world, no physics. Asserts
# BuildMode.LINE_3C_SEQ stays index-aligned with Line3CDef.STAGES, because a
# machine's plant address (l3c_code) is DERIVED from its macro_index -- inserting
# or reordering one SEQ row silently re-addresses every later stage and would
# hand L3C.9R's 30.88 A to L3C.10L. Mutation: swap two rows -> red.
# test_line3c_identity: the killer check, on a REAL MainWorld boot (a bench green
# is worthless here -- npc-05 printed 31/31 while moving zero kg). Places the
# line_3c macro and asserts each of the FIVE friction separators reads ITS OWN
# calibrated nominal (29.92 / 29.92 / 28.03 / 30.88 / 24.68 A -- FOUR distinct
# values, because Line3CDef.gd gives 4L and 4R the same 29.92; five distinct
# numbers would mean one was invented), that L3C.14L carries 70.80 A nominal
# instead of the 0.00 A it read before, that sum(amps_nominal) == 488.49 A, and
# that the mass ledger still balances now that stamping also swaps in the
# ProcessModel transfer coefficients and switches on the dryer pair controller.
for t in test_qa_spec test_map_frame test_nested_vehicle_drift test_npc_target_guard test_feeder_fetch test_vehicle_spawn_frame test_nav_connectivity test_outdoor_route test_jam_baseline test_gate_carve test_line3c_seq_alignment test_line3c_identity test_tag_snapshot test_waslijn3c_overzicht test_lump_cart_coverage test_l3c_unit_screens; do
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
