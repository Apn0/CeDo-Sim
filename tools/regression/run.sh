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

# HERMETIC. Without this every single suite below reaches the public internet:
# PolyhavenMaterials._ready() requests its PBR sets at autoload boot
# (PolyhavenMaterials.gd:84) and TextureCache opens an HTTPRequest to the
# Polyhaven API for anything not already on disk (TextureCache.gd:96-101). That
# made a regression harness quietly dependent on a third party being up, on the
# machine having a network, and on nobody rate-limiting us — none of which any
# suite here actually asserts anything about.
#
# Safe by construction, not by hope: no wired suite references PolyhavenMaterials,
# TextureCache or pbr_set_ready at all (grepped), and the offline path is a
# documented degrade rather than a failure — _build(kind) still produces the
# flat-colour StandardMaterial3D and only the HD upgrade never arrives
# (PolyhavenMaterials.gd:70). test_texture_cache is immune because it sets
# CEDO_OFFLINE explicitly to both values itself and restores what it found.
#
# Export, so it reaches every child Godot process below.
export CEDO_OFFLINE=1

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

# FULL-TREE PARSE SWEEP. The gate above boots the main scene — MainMenu.tscn —
# which loads none of src/build, src/sim or src/scenes/world, so it cannot see a
# broken file in any of them. Measured 2026-08-23: merge 7b72ecf left `grp_hot`
# (a local of a DIFFERENT function) in PlaceableCatalog.gd:11071, the gate above
# printed clean, and LineFlow, BuildMode and every world suite were dead. A
# suite whose script fails to compile does not fail — it boots with no script
# attached and idles forever, which is the "hang" this repo has now chased twice.
#
# This used to sweep src/tests/*.gd only, one `--check-only` engine start per
# file. That version WOULD have gone red here, but with 27 test files all
# reporting the same inherited error and the actual culprit — a non-test file —
# never named. It now sweeps the whole tree, names the root file, and does it in
# one boot: ~15 s against the ~6 min the 312-start loop cost.
#
# Gated on ERR_PARSE_ERROR only, for the same reason as before: see the header of
# parse_sweep.gd for the measurement, for the 47 ungated ERR_COMPILATION_FAILED
# notes, and for the two detectors that were tried and failed their mutation.
echo "== full-tree parse sweep =="
"$GODOT" --headless --path "$PROJ" \
	--script res://tools/regression/parse_sweep.gd > "$OUT/parse_sweep.log" 2>&1
grep -E "^===|^  FAIL|^note  :|^Result:" "$OUT/parse_sweep.log" || true
if ! grep -q "^RESULT: PASS" "$OUT/parse_sweep.log"; then
	echo "FAIL  : one or more project scripts do not parse (see $OUT/parse_sweep.log)"
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

# SYMBOL FLOW. Generalises the `_live_pieces` bug (occurred once in the whole
# repo, blocked every test for 3 weeks) into a repeatable check: every private
# symbol must be declared, written AND read somewhere. Mutation-tested against
# the pre-fix BaleBurst.gd — see docs/audit/material_trace_2026-08-18.md.
echo "== symbol flow audit =="
if ! python3 "$PROJ/tools/audit/symbol_flow.py" --root "$PROJ/src" --all; then
	echo "FAIL  : an undeclared/write-only/dead symbol was found (see above)"
	exit 1
fi

# MATERIAL CENSUS. Every stage that consumes a MaterialBatch must also emit
# one (or be a documented plant boundary) — the operator's "every input has an
# output" framing, applied to the conserved mass/water/contaminant quantities
# directly rather than to code symbols. Same audit session, same doc.
echo "== material census =="
if ! python3 "$PROJ/tools/audit/material_census.py" --root "$PROJ/src"; then
	echo "FAIL  : a material stage mints, sinks, or drops a sub-mass (see above)"
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
# test_project_sweep_guards: the three findings of the 2026-08-23 sweep, each of
# which had already survived a review. A — the hot strand group owns ONE smoke
# MultiMesh and ZERO loose per-strand wisps (the reverted form of that loop is
# what stopped PlaceableCatalog.gd parsing and hung every world suite). B — a
# wall placed through BuildMode's own two-point path reaches
# WorldLayout.structure_items with both endpoints; before the fix it carried no
# placeable_id, so _save_layout skipped it and every hand-built partition was
# gone on reload. C — crew TTS is connected, and connected exactly once; C is
# also the record that FULL_LOGIC_AUDIT #12 is REFUTED, since it is green with
# and without that finding's prescribed fix. All three mutation-proven; see the
# file header and docs/AUDIT_project_sweep_2026-08-23.md.
# test_line3a_identity / test_line3b_identity (2026-08-27): the same
# ledger_residual() conservation claim as test_line3c_identity, extended to
# line_3a and line_3b (docs/audit/material_trace_2026-08-18.md: "macros exist
# for line_3a, line_3b, line_1, line_sort, line_intake_3a3b -- none of them
# assert the ledger"). Neither line has a Line3ADef/Line3BDef HMI-current
# table like line_3c's, so these two make no per-instance amps claim -- only
# the mass ledger, on a real MainWorld boot, fed at the documented 1000 kg/h
# per-line design rate (docs/plant/misc_sources.md:190/206). line_1 and
# line_sort/line_intake_3a3b remain unasserted -- no documented feed-rate
# source was found for line_1, and the other two are out of scope.
# test_line_builder_ghost (2026-08-29): operator report — placing a whole-line
# macro (Line 1, ~40+ machines) only showed a generic single box + arrow as
# the ghost, no way to see where the REST of the train would land before
# committing. BuildMode._build_full_line grew a `preview` param that reuses
# the SAME position math (turns/branches/transportband stacking/at_entry/
# saved deltas) as the real build but emits cheap unparented placeholder
# boxes instead of real machines with zero side effects on _placed_root or
# LineFlow. Also covers the pinned "NEW LINE BUILDER" catalog section asked
# for in the same report. Mutation-tested: skipping preview entries past
# index 0 (simulating the pre-fix single-box ghost) drops the ghost from 50
# children to 1 and breaks the real-vs-preview count parity check — red.
for t in test_map_frame test_nested_vehicle_drift test_npc_target_guard test_feeder_fetch test_vehicle_spawn_frame test_nav_connectivity test_outdoor_route test_jam_baseline test_gate_carve test_line3c_seq_alignment test_line3c_identity test_line3a_identity test_line3b_identity test_tag_snapshot test_waslijn3c_overzicht test_lump_cart_coverage test_hmi_retired test_bale_yard_mass_conservation test_belt_discharge_geometry test_hmi_screen_zeroing test_l3c_unit_screens test_npc05_realworld test_humanoid_rig_conformance test_line1_flow_conformance test_line3a_flow_conformance test_line3b_flow_conformance test_shredder_rate_reconciliation test_line1_no_false_overload test_line_builder_ghost test_project_sweep_guards; do
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

# npc-05 container chain bench: DELETED 2026-08-17 on operator order along with
# the bench worlds it ran on. It was 31/31 green while the chain was DEAD in a
# real session -- the canonical example of why a bench green proves the mock.
# Coverage for the container chain now belongs in a real MainWorld boot:
# test_npc05_realworld, gated above in the "for t in test_..." loop like every
# other real-boot proof. It is EXPECTED to report FAIL until the DRIVE_TO_INDOOR
# stall is fixed (worker boards the forklift, then the 33.9 m indoor leg to the
# target bin never closes) -- see CLAUDE.md's "The npc-05 container chain stalls
# at DRIVE_TO_INDOOR" section for the measured cause. A red result here is the
# harness doing its job, not a regression; do not silence it by pulling the
# test back out of the loop.

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

# MotorOverload unit test — existed since before this session but was NEVER
# wired into the harness. Now guards the 2026-08-29 set_load() fix directly:
# LineFlow used to call add_load(_backlog_kg) every tick (a STOCK re-added as
# if it were a fresh inflow event each time), so any high-load node with even
# a small, perfectly steady buffer would eventually false-trip — measured on
# line 1's real 'mill' node, buffer under 7 kg throughout, still raced to a
# full 450 A trip in ~10 s. set_load() mirrors the stock directly instead.
echo "== motor overload (set_load fix + trip/reset logic) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_motor_overload.gd > "$OUT/motor_overload.log" 2>&1
grep -E "^\[|^  ok|^  FAIL|^Result:" "$OUT/motor_overload.log" || true
if ! grep -qE "^Result: [0-9]+ ok, 0 fail" "$OUT/motor_overload.log"; then
	echo "FAIL  : motor overload (see $OUT/motor_overload.log)"
	[ $code -eq 0 ] && code=1
fi

# HmiWebOverlay (task #2): the WebView itself can't exist headless, so this
# covers everything Godot owns around it — Index-derived nav order, the
# unknown-screen refusal, and gather_vals()' LineFlow -> shell payload
# (calibrated amps per plant code, 4-state line pill, estop fault flag).
echo "== hmi web overlay (nav + vals logic) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_hmi_web.gd --quit-after 300 > "$OUT/hmi_web.log" 2>&1
grep -E "^  ok|RESULT FAIL|PASS —" "$OUT/hmi_web.log" || true
if ! grep -q "PASS —" "$OUT/hmi_web.log"; then
	echo "FAIL  : hmi web overlay (see $OUT/hmi_web.log)"
	[ $code -eq 0 ] && code=1
fi

# ---------------------------------------------------------------------------
# Unit suites from the 2026-08-29 PR batch (#154-#165). Every one of them was
# merged to main and then executed by NOTHING: the .tscn allow-list above never
# named them, so the only thing that had ever looked at them was the full-tree
# parse sweep, which proves a file PARSES and makes no claim about what it does.
# docs/audit/pr_merge_2026-08-29.md measured that gap ("The finding that
# outlives this merge"); this block and the loop entry above close it.
#
# Two things had to change before wiring them was even safe:
#
#   1. test_wall_openings.gd and test_push_gate.gd asserted with bare assert().
#      A failing assert() aborts the enclosing function BEFORE its quit(), so
#      the SceneTree keeps iterating and the process idles — the harness HANGS
#      instead of going red (the "idles forever" mode at run.sh:48-54). Both now
#      count checks and reach a verdict on every path. assert() is ALSO compiled
#      out of release builds, and $GODOT is overridable by design (run.sh:17-21)
#      precisely so this harness can run off a template on Linux/CI — under that
#      binary the old files would have run top to bottom checking nothing at all
#      and printed a pass. The counted form is the only one immune to both.
#
#   2. The gate below is `Result: <n> ok, 0 fail` with n >= 1, NOT `Result: PASS`.
#      A suite that executed zero checks prints PASS perfectly honestly; demanding
#      a non-zero count is what makes "it ran but did nothing" red. Same reason
#      the motor-overload gate at run.sh:344 is written that way.
#
# --quit-after 300 on each: --quit-after counts main-loop ITERATIONS, not
# seconds, so a slow machine cannot false-fire it (slowness makes an iteration
# longer, not more numerous, and all three do their work inside one). It is the
# backstop that turns an abort-before-quit into a red instead of a hang, and 300
# is reused from the hmi_web invocation above rather than inventing a number.
echo "== wall openings (carve bookkeeping, unit) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_wall_openings.gd --quit-after 300 > "$OUT/wall_openings.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/wall_openings.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/wall_openings.log"; then
	echo "FAIL  : wall openings (see $OUT/wall_openings.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== push gate (free-side local-space math, unit) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_push_gate.gd --quit-after 300 > "$OUT/push_gate.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/push_gate.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/push_gate.log"; then
	echo "FAIL  : push gate (see $OUT/push_gate.log)"
	[ $code -eq 0 ] && code=1
fi

# TextureCache: disk-cache hit path, manifest bookkeeping, corrupt-entry eviction.
# The suite forces its own instance offline before the corrupt-entry case (see the
# comment at that line) so this harness never opens a socket to the Polyhaven API.
echo "== texture cache (disk cache + manifest, unit) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_texture_cache.gd --quit-after 300 > "$OUT/texture_cache.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/texture_cache.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/texture_cache.log"; then
	echo "FAIL  : texture cache (see $OUT/texture_cache.log)"
	[ $code -eq 0 ] && code=1
fi

# Walkie (#161). docs/audit/pr_merge_2026-08-29.md holds this suite back as
# measured-broken: mocks silently overridden by the real autoloads, a failure at
# line 60, and a reachable TTS backend. That was true of the PR AS REVIEWED and
# is NOT true of what was merged — the author reworked it, and the fix is the
# /root rename block now at the top of _run_tests. Re-measured 2026-08-30 on the
# merged file: 35 ok, 0 fail, exit 0, no hang. The audit doc has been corrected.
# Safe because Walkie caches neither dependency — every AudioManager/VoiceService
# touch is a fresh get_node_or_null("/root/...") (Walkie.gd:175/238/267/277/303),
# so renaming the real nodes before the first call is sufficient, and the real
# VoiceService (the only OS.execute in src/, VoiceService.gd:524) is never
# reached. Four VoiceService checks that an `if vs.calls.size() > 0:` guard had
# made vacuous were de-guarded when it was wired; they pass hard.
echo "== walkie (battery/headset/PTT + dead-battery silence, unit) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_walkie.gd --quit-after 300 > "$OUT/walkie.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/walkie.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/walkie.log"; then
	echo "FAIL  : walkie (see $OUT/walkie.log)"
	[ $code -eq 0 ] && code=1
fi

# #A3 silo level sensor. build_node() picks a body class from a long if/elif
# chain, and this entry's category is "Control" — so while the `category ==
# "Control"` arm was tested BEFORE the `id == "silo_level_sensor"` arm, the id
# arm was UNREACHABLE and every placed sensor silently got Hmi.gd. That one line
# was the ONLY instantiation of SiloLevelSensor.gd in the repo, so LineFlow's
# get_nodes_in_group("silo_level_sensor") index (LineFlow.gd:410) was permanently
# empty and #A3 had never run in any build. TagMap.gd:60 had already recorded the
# downstream symptom ("current_level_pct IS A DEAD SOURCE") without anyone
# tracing it back to the ordering. Mutation-proven: restoring the old order turns
# 3 checks red with "got: res://src/build/Hmi.gd" and exits 1.
# An ordering bug is invisible to the parse sweep and to any check that only asks
# whether the catalog HAS an entry — this one builds the node and reads its script.
echo "== silo level sensor wiring (#A3) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_silo_level_sensor_wired.gd --quit-after 300 > "$OUT/silo_level_sensor.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/silo_level_sensor.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/silo_level_sensor.log"; then
	echo "FAIL  : silo level sensor wiring (see $OUT/silo_level_sensor.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== done (exit $code) — see $OUT/topdown.png =="
exit $code
