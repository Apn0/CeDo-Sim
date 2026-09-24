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

# HANG GUARD for the scene-suite loop below. That loop passes no --quit-after and
# had no timeout, so one suite that never reaches its own quit() (a script that
# failed to attach, a wait that never resolves — the documented "idles forever"
# mode) stalled the WHOLE harness with nothing printed. `timeout` was measured on
# 2026-09-21 to kill a hung headless Godot on schedule (rc 124, no process left
# behind). 900 s is 4.4x the slowest scene-loop suite in the 29-minute full run
# of that day (test_npc05_realworld, 206 s — it watches 180 s by design; derived
# from log mtimes). Override with SUITE_TIMEOUT_S=; without a `timeout` binary the
# guard is simply absent.
SUITE_TIMEOUT_S="${SUITE_TIMEOUT_S:-900}"
if command -v timeout >/dev/null 2>&1; then
	SUITE_TO=(timeout --kill-after=15 "$SUITE_TIMEOUT_S")
else
	SUITE_TO=()
fi

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
# #CRLF-fix: parse_sweep.gd runs inside Godot (Windows build) and emits \r\n.
# bash grep -q "^RESULT: PASS" treats \r as part of the line content so the
# anchor match fails — the line is "RESULT: PASS\r" not "RESULT: PASS".
# Strip \r before the grep so this check works on both Windows and Linux CI.
if ! tr -d '\r' < "$OUT/parse_sweep.log" | grep -q "^RESULT: PASS"; then
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
# test_macro_part_placement (2026-09-16): operator report — a cluster of stray
# panels and hinges floating at roughly (0, 3, 0) in the built world. 47 visible
# meshes on line 1 resolved >40 m from their own machine (shredder_1's hatch at
# global (1.76, 3.19, 0.00) while the shredder stood at (-156.76, 0, 38.98)).
# Cause: AnimatableBody3D.sync_to_physics defaults to TRUE, so Godot drives the
# body FROM the physics server, and the server is only notified when the body's
# OWN transform is written — moving an ANCESTOR never reaches it. Machines are
# built at the catalog's local origin and moved into place by the macro AFTER,
# so each such body stayed pinned to the global transform it had at build time,
# which was its intended LOCAL offset. Fixed at all three construction sites
# (PlaceableCatalog._interactive_hatch, PushGate._build_hinge_pivot,
# Door._build_hinge_pivot) and, for hatches, enforced in InteractiveHatch._ready
# so a fourth site cannot forget. Nothing caught it before: the geometry suites
# assert where MACHINES land, never where a machine's own PARTS land relative
# to it. This asserts that missing invariant over three macros, each built at a
# start far from the world origin — building at Vector3.ZERO would hide the
# entire bug class. MUTATION-TESTED twice, on two different code paths, both
# red on all three macros: sync_to_physics=true at the catalog hatch site gave
# 37/14/18 stray parts at 143-265 m, and at PushGate._build_hinge_pivot gave
# 10/10/10 stray silo-gate leaves at 143-266 m. Green run for comparison:
# 451/279/290 visible parts checked, 0 stray, worst legitimate overhang 10.5 m
# against a 17.9 m limit.
# test_tool_placement_mode (2026-08-30): merged 2026-08-29 by PRs #154/#163 and
# never run by anything until it was wired here. RE-ADDED 2026-08-31: the
# 2026-08-31 batch merge replaced this whole `for t in` line with PR #168's
# version of it, which silently dropped this suite — git merged one line over
# another with no conflict. It is a pure unit proof of ToolPlacementMode with
# no world boot, so it belongs in this loop: it ships a .tscn that roots it and
# it ends in get_tree().quit(). Its verdict print sits BELOW its teardown --
# this loop has no --quit-after, so a verdict printed before the last eleven
# statements would leave "Result: PASS" in the log with the process still
# alive: a green log and a hung harness at once.
# test_atomic_file (2026-09-21): crash-safe persistence — AtomicFile and the
# writers that now use it (WorldLayout, BuildMode, LineMacroStore, GameState,
# PlaceableCatalog size overrides). A save killed mid-write used to load back as
# an EMPTY factory / the demo-spawn world, and the 60 s autosave made that
# permanent. 50 checks, each recovery check preceded by an undamaged-file
# control, plus delete-safety (a .bak must never resurrect a deleted save).
# MUTATION-TESTED five ways, each turning specific checks red and restoring
# byte-identical: no .bak fallback (6 red), poisoned .bak (2), resurrecting
# deletes (2), the ORIGINAL BuildMode (2 red — the factory loads back with 0
# objects, i.e. the reported bug reproduced end to end), the old WorldLayout
# load (1 red — spawn (0,0,0)). It touches only `__atomicfile_*` names in user://
# and points WorldLayout at a scratch path via layout_path_override.
# test_motor_trip_stops_conveying (2026-09-23): a latched MotorOverload trip must
# actually STOP the drive. Measured before the fix: LineFlow's PLC step re-wrote
# powered=true at the top of every tick and the trip only dropped it after the
# conveying split, so a "tripped" shredder-2 kept conveying at its full 0.61 kg/s
# with 0 A on the readout, its rotors stayed at 45 rpm, and the bunker/shredder-2
# interlock moved 31 kg in 3.1 s "stopped". 28 checks on the real line_sort macro:
# anti-vacuity (both machines convey BEFORE the trip), zero kg moved and spin/rpm
# at 0 while tripped, buffer untouched (conserving), TITECH unaffected, reset
# restores conveying. Pre-fix run: 20 ok / 8 fail (the 8 are the defect).
# test_lump_cart_overflow (2026-09-23, P6): a full Lumpenwagen overflows onto the
# floor instead of losing kg, and its fill is visible. Real line_3b macro, the
# production purge path (LaserFilter._disc_advance) into a cart filled through
# receive_lump(); then line_1/3A/3C for the mound placement. Conservation check:
# shed == voor cart + floor + lost. Before: receive_lump() dropped kg at is_full()
# and nothing ever read is_full().
# test_save_checkpoint (2026-09-23, Q2): SaveCoordinator.save_checkpoint() copies
# the live slot + factory sidecar under a stamped stem the main menu lists; same-
# second stamps get -2/-3; no GameState → "" and nothing written. Real GameState +
# SaveCoordinator, __cptest__ files only, all deleted at the end (22 checks).
# test_keybind_sheet (2026-09-23, Q4): the F1 key sheet — one row per Controls-tab
# action, keys == the live InputMap, F1 owned by help_overlay alone, the sheet
# renders one row per action and follows a runtime rebind.
# test_map_labels (2026-09-23, Q5): the site map names machines by catalog display
# name, names the crew dots and draws every HMI panel with its scope label. Real
# MainWorld boot for the crew, two catalog-built HMI panels, a zoomed redraw.
# test_lump_cart_speed_clamp (2026-09-23, phys-05 interim): a Lumpenwagen can
# never be flung past LumpCart.MAX_SPEED (6 m/s) or spun past MAX_SPIN_RAD —
# the squeeze-eject between a frozen-kinematic vehicle and a wall. Mutation-
# measured: integrator disabled → 48.09 m/s / 53.33 rad/s; with it 5.76 / 5.58.
# A 1.2 m/s walking shove is untouched (anti-vacuity).
# test_vacuum_pot_visual (2026-09-23, P3 stage A): the extruder's two vacuum
# pots show ExtruderModel's state through the catalog body — the melt level
# behind each dome's sight-glass port, the lid pushed open at capacity, the
# gunk at the riser — driven every frame by the SimBrain. 22 checks.
# test_doseersilo_trough (2026-09-24, rulings §17): the doseersilo is the
# operator's open tilted trough — 22.5° up toward +Z, flat bottom, vertical
# walls, flat ends, no half-discs, no grating, lowest point 1.70 m, 2.98 m
# wide × 5.57 m long (0.9× / 1.1× the model he was shown), three augers on
# the tilted frame, four legs; LineFlow's ports low-end in / high-end out.
# 14 checks, read off the built node and a real LineFlow rebuild.
# test_bale_weight_variance (2026-09-24, rulings §18): no two bales weigh the
# same — every bale body draws its own weight (Gaussian, σ 15 %, clipped ±3 σ)
# around its origin's nominal, the RigidBody mass, the yellow label and
# LineFlow's remaining_kg all read that one figure, the light→full upgrade
# keeps it; and LINE_1_FOLIE (2.0 × 1.7 × 1.5 m, 1000 kg) exists for line 1.
# 17 checks on 40 built bales — 40 distinct weights, SD measured, ±3 σ range.
# test_wet_side_beds (2026-09-24, task 1c, rulings §1/§12): flake beds where
# the operator sees flake on the wet side — the Kufferath sieve deck (which
# now descends toward its outlet), every scheidingsgoot segment (5), the
# dewatering screw's trough (open ONLY after a flotation tank, decided from
# the LineFlow graph), the bunker deck and the doseersilo bottom — through
# build_node/StaticMerge, and driven WET by a real bale through line 1.
# test_line1_metal_detect (2026-09-24, rulings §11): line-1 bales can hide
# scrap (BaleDefs rolls it per bale; other origins never); the first conveyor's
# sensor at 3/4 trips on a metal bale → slows to a stop, reverses one full
# length, stops, runs forward, trips AGAIN on the same bale; the operator's
# stop ends the cycle; taking the scrap off the bale clears it; a belt without
# the sensor never trips; opzetband_1 is built with it, opzetband_3a3b not.
# test_vacuum_pot_minigame (2026-09-24, P3 stage B, rulings §14): a full pot
# pushes its lid → VACUUM_ALARM naming the pot; the hold-E shortcut can no
# longer clear it; the lid pull (longer the longer the vacuum is gone), the
# plamuurmes planes (push / pull out, stiffness from elapsed time), the block
# freed at 90 % and shifted 1 cm, taken out (pot emptied, mass conserved into
# a lump cart), the lid back within two minutes → RUNNING; past two minutes →
# FAULT with the laser-filter alarm on the bus. Driven headless through
# VacuumPotService on a real catalog extruder + SimBrain.
# test_belt_speed_mismatch (2026-09-24, round 8): a belt fed faster than it
# runs heaps up at its infeed (a mirrored FloorPile), its deck slows with the
# HMI speed setting, its drive trips MOTOR-OVERLOAD after 3 s over current and
# the belt stops holding its bed; at full speed the same feed never trips
# (anti-vacuity); RESETTEN clears the trip and the heap drains. Real line 1
# through BuildMode + LineFlow, an injected charge, no mocks.
# test_chute_choke (2026-09-23, P6 second half): a machine whose reject pile
# refuses material chokes — latched like a trip, one CHUTE-BLOCKED alarm,
# nothing conveyed, the refused kg back in the machine (ledger incl. wash
# water), the crew service shovels the pile, reset refused while it is full
# and taken after, survives a rebuild. 24 checks.
# test_trip_smoke (2026-09-23, P2 second half): a MotorOverload trip edge
# sometimes (chance forced to 1 / 0 here) starts a heavy SmokePlume at the
# motor housing for SMOKE_S, raises a SMOKE alarm, the crew log it; the plume
# is reused, the edge re-arms after a reset. 21 checks.
# test_silo_level_windows (2026-09-23, P5): the doseersilo, mengsilo and
# extruder silo carry the level windows the operator described (counts, sizes,
# faces, spacing), each a proud sight-glass port with a film witness that
# set_silo_fill() drives; LineFlow drives it from the node's buffer; the
# compactor kijkglas rides the same port (the morning's flat glass showed
# nothing — measured by render). 50 checks.
# test_belt_film_field (2026-09-23, P1): every conveyor deck carries a
# FilmFlakeField in belt mode, seated on the deck skin's top face (measured
# unmerged, and through build_node's static merge); the bed is kg/m =
# thru / deck speed over a per-stage bulk density; a HAND-off belt holds its
# bed; colour order and size spread as the operator described; line 1 booted
# for real with a steady injection. 118 checks. Also pins the inclined belt's
# deck to the diagonal its rollers climb (it ran the other diagonal before).
# test_compactor_sight_glass (2026-09-23): SWI-012 p7 step 6 "Vul de compactor op
# hand tot het kijkglas" — the flake column behind the compactor's sight glass IS
# CutterCompactor's pot load. Geometry read off the mesh's own meta, the glass
# window proven inside the fill range, and the production LineFlow path driving
# the column tick by tick from an injected charge.
for t in test_motor_trip_stops_conveying test_lump_cart_overflow test_lump_cart_speed_clamp test_save_checkpoint test_keybind_sheet test_map_labels test_compactor_sight_glass test_belt_film_field test_silo_level_windows test_chute_choke test_trip_smoke test_vacuum_pot_visual test_doseersilo_trough test_bale_weight_variance test_wet_side_beds test_line1_metal_detect test_vacuum_pot_minigame test_belt_speed_mismatch test_map_frame test_nested_vehicle_drift test_npc_target_guard test_feeder_fetch test_vehicle_spawn_frame test_nav_connectivity test_outdoor_route test_jam_baseline test_gate_carve test_line3c_seq_alignment test_line3c_identity test_line3a_identity test_line3b_identity test_tag_snapshot test_waslijn3c_overzicht test_lump_cart_coverage test_hmi_retired test_bale_yard_mass_conservation test_belt_discharge_geometry test_hmi_screen_zeroing test_l3c_unit_screens test_npc05_realworld test_humanoid_rig_conformance test_line1_flow_conformance test_line1_throughput test_line1_overband_mount test_line1_twin_streams test_line3a_flow_conformance test_line3b_flow_conformance test_shredder_rate_reconciliation test_line1_no_false_overload test_line_builder_ghost test_macro_part_placement test_project_sweep_guards test_tool_placement_mode test_scada_dashboard_scene test_atomic_file test_extruder_brain_wired test_vehicle_census test_map_overlay_init test_qa_loop test_qa_spec test_assessment_procedure test_character_customizer test_f10_reserved test_bale_sticker_supplier test_hose_reel_round test_macro_delta_guard; do
	echo "== $t =="
	${SUITE_TO[@]+"${SUITE_TO[@]}"} "$GODOT" --headless --path "$PROJ" "res://src/tests/$t.tscn" > "$OUT/$t.log" 2>&1
	rc=$?
	[ "$rc" -eq 124 ] && echo "TIMEOUT: $t hung past ${SUITE_TIMEOUT_S}s and was killed (no verdict was printed)"
	grep -E "^  (ok|FAIL)|Result|RESULT" "$OUT/$t.log" || true
	# Key off the printed verdict, not the exit code: Godot can segfault in
	# teardown after a clean PASS (observed exit 139 with every check ok).
	if ! grep -qE "Result: PASS|RESULT: PASS" "$OUT/$t.log"; then
		echo "FAIL  : $t (see $OUT/$t.log)"
		[ $code -eq 0 ] && code=1
	fi
done

# 2026-09-21 — SUITES THAT WERE NEVER RUN. 34 test scenes existed that nothing
# invoked (found by diffing src/tests/*.tscn against this file). 26 of them were
# measured green that day and are wired here / above (11 already print the
# canonical `Result: PASS` and joined the loop above). The other 15 print their
# verdict in their OWN dialect (docs/audit/test_inventory_2026-09-06.md §6), which
# the loop above would score as a false red. Loosening that loop's grep would let
# any suite's stray "PASS" bless another, so each suite here is gated on ITS OWN
# exact verdict line, and must also have printed at least one `  ok` (a 0-check
# suite is a vacuous green, project rule 3) and no `  FAIL`.
# Each pattern was proven against the real log of its suite and REJECTS the logs
# of the two red suites (test_feed_belt_to_shredder_flow,
# test_line1_automated_4bales — both untracked local files, not in git) — see
# docs/audit/robustness_and_coverage_2026-09-21.md.
# NOT wired, on purpose: test_marker_tool (writes into the operator's real
# user://feedback channel and leaves the directory there), the three suites that
# print no verdict at all (test_leafblower_refuel, test_player_ladder,
# test_hmi_screen_base — the last runs 0 checks), and the two red ones above.
dialect_re() {
	case "$1" in
		test_layout_load|test_new_world_wipe|test_world_layout_coords|test_cutter_compactor|test_extruder_screw|test_mast_jib|test_merlo_p40|test_spawn_transform)
			echo '^Result: [0-9]+ ok, 0 fail' ;;
		test_appearance_persistence)        echo '^\[TEST\] appearance persistence PASS' ;;
		test_customizer_resolves_gamestate) echo '^\[TEST\] customizer resolve PASS' ;;
		test_bunker_relay_trip)             echo '^\[TEST\] bunker relay trip PASS' ;;
		test_bunker_shredder2_interlock)    echo '^\[TEST\] bunker/shredder-2 MOL interlock PASS' ;;
		test_feeder_sequence)               echo '^\[TEST\] feeder sequence PASS' ;;
		test_npc_appearance_apply)          echo '^\[TEST\] npc appearance apply PASS' ;;
		test_shredder_machine)              echo '^\[TEST\] shredder machine PASS' ;;
	esac
}
for t in test_layout_load test_new_world_wipe test_world_layout_coords test_cutter_compactor test_extruder_screw test_mast_jib test_merlo_p40 test_spawn_transform test_appearance_persistence test_customizer_resolves_gamestate test_bunker_relay_trip test_bunker_shredder2_interlock test_feeder_sequence test_npc_appearance_apply test_shredder_machine; do
	echo "== $t (own-dialect verdict) =="
	${SUITE_TO[@]+"${SUITE_TO[@]}"} "$GODOT" --headless --path "$PROJ" "res://src/tests/$t.tscn" > "$OUT/$t.log" 2>&1
	rc=$?
	[ "$rc" -eq 124 ] && echo "TIMEOUT: $t hung past ${SUITE_TIMEOUT_S}s and was killed (no verdict was printed)"
	re="$(dialect_re "$t")"
	grep -aE "^  (ok|FAIL)|^Result|^\[TEST\]" "$OUT/$t.log" | tail -3 || true
	if ! tr -d '\r' < "$OUT/$t.log" | grep -aqE "$re"; then
		echo "FAIL  : $t — its own verdict line ($re) was not printed (see $OUT/$t.log)"
		[ $code -eq 0 ] && code=1
	elif tr -d '\r' < "$OUT/$t.log" | grep -aqE '^  FAIL'; then
		echo "FAIL  : $t — verdict line printed but a check reported FAIL (see $OUT/$t.log)"
		[ $code -eq 0 ] && code=1
	elif ! tr -d '\r' < "$OUT/$t.log" | grep -aqE '^  ok'; then
		echo "FAIL  : $t — verdict printed but ZERO checks ran (vacuous) (see $OUT/$t.log)"
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
	if ! tr -d '\r' < "$OUT/spawn_clearance_$cfg.log" | grep -qE "^Result: PASS"; then
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


# SettingsManager.set_pending_keybind

echo "== SettingsManager set_pending_keybind =="

"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_settings_manager_pending_keybinds.gd --quit-after 300 > "$OUT/settings_manager_pending_keybinds.log" 2>&1

grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/settings_manager_pending_keybinds.log" || true

if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/settings_manager_pending_keybinds.log"; then

	echo "FAIL  : SettingsManager pending keybinds (see $OUT/settings_manager_pending_keybinds.log)"

	[ $code -eq 0 ] && code=1

fi



# =============================================================================
# 2026-08-31 REVIEW SUITES. Nine suites from the external review of that date
# (docs/audit/review_findings_2026-08-31.md): eight new + test_inventory, which
# had existed unwired since it was written. All are SceneTree --script suites in
# the counted-check shape — the [1-9][0-9]* gate refuses both a red run and a
# vacuous "0 ok" run, and --quit-after 300 (main-loop iterations, not seconds)
# bounds a hang without being able to false-fire on a slow machine.
# =============================================================================
# Gate.gd state semantics (2026-08-31 review finding: is_fully_open/is_fully_closed
# at src/build/Gate.gd:101/104 were untested). Proves the 0.999/0.001 threshold
# boundaries, set_drive clamping to [-1,1], and _physics_process travel with
# limit-switch auto-stop and [0,1] clamping, via direct deterministic dt stepping.
echo "== Gate state (is_fully_open / is_fully_closed / drive) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_gate_state.gd --quit-after 300 > "$OUT/gate_state.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/gate_state.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/gate_state.log"; then
	echo "FAIL  : Gate state (see $OUT/gate_state.log)"
	[ $code -eq 0 ] && code=1
fi

# VehicleRouteGrid.goal_clearance — route() deliberately appends the RAW ordered
# pose as its final waypoint (a goal is routinely inside a container or a cart
# pocket), so before 2026-09-03 a caller could not tell a reachable goal from one
# inside a machine. Measured cost: test_jam_baseline ordered a forklift onto
# player_spawn and it orbited for 352 m with nothing reporting why. Unit form on a
# synthetic occupancy grid — no world boot, no A*, no physics, milliseconds.
echo "== VehicleRouteGrid goal clearance =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_route_goal_clearance.gd --quit-after 300 > "$OUT/route_goal_clearance.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/route_goal_clearance.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/route_goal_clearance.log"; then
	echo "FAIL  : VehicleRouteGrid goal clearance (see $OUT/route_goal_clearance.log)"
	[ $code -eq 0 ] && code=1
fi

# ScadaDashboard public API — set_state (state stored verbatim, grey-iff-Running colour,
# micro-stop true/false return incl. exact-60s boundary), set_param (in/above/below band ->
# grey/red/amber + is_param_alarming, repeat key updates not duplicates), set_text_param
# (is_alarming true/false, sentinel alarm flag, em-dash empty text). 2026-08-31 review finding.
echo "== ScadaDashboard API (set_state/set_param/set_text_param) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_scada_dashboard.gd --quit-after 300 > "$OUT/scada_dashboard.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/scada_dashboard.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/scada_dashboard.log"; then
	echo "FAIL  : ScadaDashboard API (see $OUT/scada_dashboard.log)"
	[ $code -eq 0 ] && code=1
fi

# ShredderFeedBelt public API — request_start/request_stop (:416), fault latches
# is_faulted/belt_jam_active/reset_faults (:541), and can_accept/accept_bale gates (:605),
# all untested per the 2026-08-31 review. State-only SceneTree suite (no physics stepping);
# scope split from test_shredder_feed_belt.gd (held_kg conservation) and test_feed_belt_orientation.gd (#211a timer).
echo "== ShredderFeedBelt public API =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_shredder_feed_belt_api.gd --quit-after 300 > "$OUT/shredder_feed_belt_api.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/shredder_feed_belt_api.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/shredder_feed_belt_api.log"; then
	echo "FAIL  : ShredderFeedBelt public API (see $OUT/shredder_feed_belt_api.log)"
	[ $code -eq 0 ] && code=1
fi

# HmiOverlay open_for/is_open/close_overlay — real class, real _ready (2026-08-31 review).
# Proves: fresh overlay closed; open_for sets station/header, deep-copies scope, picks the
# scope-correct HOOFDMENU tile grid, resolves LineFlow via the line_flow group; re-open replaces
# scope wholesale + clears MACHINES selection; close tears down subscope; double-close harmless.
echo "== HmiOverlay open/close =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_hmi_overlay_open_close.gd --quit-after 300 > "$OUT/hmi_overlay_open_close.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/hmi_overlay_open_close.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/hmi_overlay_open_close.log"; then
	echo "FAIL  : HmiOverlay open/close (see $OUT/hmi_overlay_open_close.log)"
	[ $code -eq 0 ] && code=1
fi

# MapOverlay.handle_zoom — direction (+1 in / -1 out), dir=0 else-branch, 50x
# repeated clamping pinned EXACTLY at MIN_RADIUS/MAX_RADIUS without overshoot,
# and the downstream effect: zoom drives view_params().scale_px and the _to_px
# pixel projection _draw() consumes (2026-08-31 review: handle_zoom untested).
echo "== MapOverlay zoom =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_map_overlay_zoom.gd --quit-after 300 > "$OUT/map_overlay_zoom.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/map_overlay_zoom.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/map_overlay_zoom.log"; then
	echo "FAIL  : MapOverlay zoom (see $OUT/map_overlay_zoom.log)"
	[ $code -eq 0 ] && code=1
fi

# test_inventory.gd existed but was wired NOWHERE (found during the 2026-08-31
# review's preload work). It directly
# guards src/autoload/Inventory.gd (take/mass/is_full/slots) and just proved it can go
# red under mutation. It is a SceneTree --script suite predating the two-line verdict
# convention: it prints only "Result: N ok, M fail" (no "Result: PASS" line), so it
# cannot join the .tscn for-loop — key off the counted verdict instead.
echo "== test_inventory =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_inventory.gd --quit-after 300 > "$OUT/test_inventory.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/test_inventory.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/test_inventory.log"; then
	echo "FAIL  : test_inventory (see $OUT/test_inventory.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== test_operator_context =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_operator_context.gd --quit-after 300 > "$OUT/test_operator_context.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/test_operator_context.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/test_operator_context.log"; then
	echo "FAIL  : test_operator_context (see $OUT/test_operator_context.log)"
	[ $code -eq 0 ] && code=1
fi

# npc_board_vehicle / npc_vehicle_of (16 checks, incl. the legacy-NPC
# set_physics_process(false) path). Written as test_operator_context.gd by
# 69013ab; a second bot PR (1b5907f) created a DIFFERENT test under the same
# name and merge #268 (30cc5f4) kept only that one. Restored 2026-09-21 under
# its own name from 58a95ba — measured 16 ok, 0 fail on 34bd56c.
echo "== test_operator_context_board_vehicle =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_operator_context_board_vehicle.gd --quit-after 300 > "$OUT/test_operator_context_board_vehicle.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/test_operator_context_board_vehicle.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/test_operator_context_board_vehicle.log"; then
	echo "FAIL  : test_operator_context_board_vehicle (see $OUT/test_operator_context_board_vehicle.log)"
	[ $code -eq 0 ] && code=1
fi

# test_hmi_universal_interactive (2026-09-17 HMI work, wired 2026-09-22): an
# operator setpoint typed on the web HMI must reach the machine model and move
# its actual value — extruder screw rpm and zone temps, the SV compactor's pot
# temperature and power cap, and generic per-screen setpoints — and an active
# e-stop must decay a running frequency. It existed untracked for five days and
# nothing ran it; measured 22 ok, 0 fail on the working tree it was written in.
echo "== test_hmi_universal_interactive =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_hmi_universal_interactive.gd --quit-after 300 > "$OUT/test_hmi_universal_interactive.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/test_hmi_universal_interactive.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/test_hmi_universal_interactive.log"; then
	echo "FAIL  : test_hmi_universal_interactive (see $OUT/test_hmi_universal_interactive.log)"
	[ $code -eq 0 ] && code=1
fi

# NPC state-API suite (2026-08-31 review): pins the four NPC.gd transition APIs —
# set/clear_autonomy_destination (:61, incl. #202 boarded routing to the chassis),
# assign/clear_forced_task (:207, real start()/release() lifecycle), assign_post/
# return_to_post/clear_post (:956), board/disembark_vehicle (:87, real OperatorContext).
echo "== NPC boarding logic =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_npc_boarding.gd --quit-after 300 > "$OUT/npc_boarding.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/npc_boarding.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/npc_boarding.log"; then
	echo "FAIL  : NPC boarding logic (see $OUT/npc_boarding.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== NPC state API (autonomy dest / forced task / post / vehicle) =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_npc_state_api.gd --quit-after 300 > "$OUT/npc_state_api.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/npc_state_api.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/npc_state_api.log"; then
	echo "FAIL  : NPC state API (see $OUT/npc_state_api.log)"
	[ $code -eq 0 ] && code=1
fi

# 2026-08-31 review: 'LaserFilterScope setup and update untested' (LaserFilterScope.gd:558).
# Line 558 is setup() on the PressureBox INNER class (the outer scope has no setup/update).
# Suite proves PressureBox.setup() builds the real Control tree (label text/colour, min sizes,
# panel StyleBoxFlat) and update() formats the value, clamps the gauge fill 0..1, and bands
# green/yellow/red at the documented 250/300-bar bounds (318-bar trip stays red).
echo "== LaserFilterScope PressureBox =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_laserscope_pressure_box.gd --quit-after 300 > "$OUT/laserscope_pressure_box.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/laserscope_pressure_box.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/laserscope_pressure_box.log"; then
	echo "FAIL  : LaserFilterScope PressureBox (see $OUT/laserscope_pressure_box.log)"
	[ $code -eq 0 ] && code=1
fi

# gather_vals() payload proof (2026-08-31 review: HmiWebOverlay.gd:275 untested in
# counted-check shape). Mocks the exact read API: LineFlow group node, /root/
# NpcAutonomyBoard, ShiftClock via tree fallback. Proves units/pills/alarm/clock
# derivation, per-code exclusions, 0.05 boundary, and every degrade path.
echo "== hmi web gather_vals =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_hmi_web_gather_vals.gd --quit-after 300 > "$OUT/hmi_web_gather_vals.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/hmi_web_gather_vals.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/hmi_web_gather_vals.log"; then
	echo "FAIL  : hmi web gather_vals (see $OUT/hmi_web_gather_vals.log)"
	[ $code -eq 0 ] && code=1
fi

# CharacterCustomizer._rebuild_world_bodies — promoted 2026-08-31 from the review
# mutation probe: no other wired suite observes this loop, so the same-day
# find_child->cached-lookup perf change would otherwise be invisible to the harness.
# Proves nested-NPC resolution, first-match-in-tree-order, ghost-name tolerance,
# and the one-body invariant across a second rebuild.
echo "== customizer world bodies =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_customizer_world_bodies.gd --quit-after 300 > "$OUT/customizer_world_bodies.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/customizer_world_bodies.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/customizer_world_bodies.log"; then
	echo "FAIL  : customizer world bodies (see $OUT/customizer_world_bodies.log)"
	[ $code -eq 0 ] && code=1
fi

# Re-wired 2026-09-21: merge #258 (6338e79) resolved its conflict by REPLACING
# this block with the gate test below, so the suite silently stopped running
# while its test file stayed in the tree. Measured 5 ok, 0 fail on 34bd56c.
echo "== SettingsManager apply =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_settings_manager_apply.gd --quit-after 300 > "$OUT/settings_manager_apply.log" 2>&1
grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/settings_manager_apply.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/settings_manager_apply.log"; then
	echo "FAIL  : SettingsManager apply (see $OUT/settings_manager_apply.log)"
	[ $code -eq 0 ] && code=1
fi

# Gate is_fully_closed specific test to ensure explicit coverage of this function

echo "== camera rig set first person camera =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_camera_rig_set_first_person_camera.gd --quit-after 300 > "$OUT/camera_rig_set_first_person_camera.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/camera_rig_set_first_person_camera.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/camera_rig_set_first_person_camera.log"; then
	echo "FAIL  : camera rig set first person camera (see $OUT/camera_rig_set_first_person_camera.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== camera rig active =="
"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_camera_rig_active.gd --quit-after 300 > "$OUT/camera_rig_active.log" 2>&1
grep -aE "^  (ok|FAIL)|^Result" "$OUT/camera_rig_active.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/camera_rig_active.log"; then
	echo "FAIL  : camera rig active (see $OUT/camera_rig_active.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== Gate is_fully_closed specific test =="

"$GODOT" --headless --path "$PROJ" --script res://src/tests/test_gate_is_fully_closed.gd --quit-after 300 > "$OUT/gate_is_fully_closed.log" 2>&1

grep -aE "^  (ok|FAIL)  |^Result:" "$OUT/gate_is_fully_closed.log" || true

if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/gate_is_fully_closed.log"; then

	echo "FAIL  : Gate is_fully_closed specific test (see $OUT/gate_is_fully_closed.log)"

	[ $code -eq 0 ] && code=1

fi

# phys-07 — LumpChunk must not tunnel the 2.5 cm cart floor. Counts PHYSICS
# TICKS, so it gets the SUITE_TO kill timer and NO --quit-after 300: measured
# 2026-09-22, --quit-after 300 ends a 150-tick run early with exit 0 and no
# verdict. The suite's own watchdog turns a mid-verdict script error into
# "Result: 0 ok, 1 fail" (exit 2) instead of a hang or a silent exit 0.
echo "== lump chunk CCD (phys-07) =="
${SUITE_TO[@]+"${SUITE_TO[@]}"} "$GODOT" --headless --path "$PROJ" --script res://src/tests/test_lump_chunk_ccd.gd > "$OUT/lump_chunk_ccd.log" 2>&1
rc=$?
[ "$rc" -eq 124 ] && echo "TIMEOUT: test_lump_chunk_ccd hung past ${SUITE_TIMEOUT_S}s and was killed (no verdict was printed)"
grep -aE "^  (ok|FAIL)|^Result" "$OUT/lump_chunk_ccd.log" || true
if ! grep -qaE "^Result: [1-9][0-9]* ok, 0 fail" "$OUT/lump_chunk_ccd.log"; then
	echo "FAIL  : lump chunk CCD (phys-07) (see $OUT/lump_chunk_ccd.log)"
	[ $code -eq 0 ] && code=1
fi

echo "== done (exit $code) — see $OUT/topdown.png =="
exit $code
