extends Node3D
## MEASURED TAG SNAPSHOT — first slice of docs/DESIGN_hmi_tag_bridge_2026-07-22.md §8.
##
##   godot --headless --path <proj> res://src/tests/test_tag_snapshot.tscn
##
## Boots the REAL MainWorld (not a bench), builds line_3a from the clean macro
## seed, powers the line, then walks LineFlow.machine_list() -> get_machine_info()
## -> TagMap and dumps every resolved tag to user://tag_snapshot.json for the
## external tool convention (engine writes user://, script reads the globalized
## path — same shape as regression_world_save.gd -> run.sh -> topdown_render.py).
##
## NON-VACUOUS PASS CRITERIA (§8, verbatim intent — not softened here)
## -------------------------------------------------------------------
##  (a) EVERY mapped row is emitted AND resolves to a non-null value:
##      absent_ids == 0, emitted == mapped, unresolved == 0, resolved == mapped.
##      The §8 wording was "resolved_tags > 0 AND non-null"; both halves of that
##      were MUTATION-PROVEN VACUOUS on 2026-07-27 and are deliberately not kept:
##        * "non-null" was a TAUTOLOGY. _emit() sets resolved := value != null, so
##          a null can never be counted resolved — the line printed "0 null" even
##          with a completely EMPTY map.
##        * "> 0" survived get_machine_info() stubbed to {}: 73 of 77 rows went
##          unresolved and the run still printed 12 ok / 0 fail / PASS, because the
##          4 line-level rows alone cleared the threshold.
##  (a2) LIVENESS, which §8 did not ask for and which nothing else here covered: a
##      get_machine_info() returning every correct KEY at its type default (all
##      false / all 0.0) also scored an identical 12 ok / 0 fail. So the run now
##      also asserts bools-true > 0, numerics-non-zero > 0, every em/status TRUE,
##      every em/snelheid > 0, >= 4 distinct numeric values, and — the one that
##      matters most — that MATERIAL ACTUALLY MOVED, because niveau / waterflow /
##      throughputactual / productioncounter are all identically 0.0 on a line that
##      is "Running" while processing nothing. That was the state of this test
##      before the feed was added: the exact npc-05 shape.
##  (b) UNIQUE ADDRESSABILITY. REWRITTEN 2026-07-29, as this file and
##      tools/regression/run.sh both said it must be the day the defect was fixed.
##      It used to assert duplicate_id_collisions != 0, MEASURING the
##      first-match addressing defect: LineFlow could only be asked for a
##      placeable id, and 14 of 47 machines on Line 3A shared an id with an
##      earlier one, so no front-end could reach them.
##      That criterion INVERTED, and it is replaced — not silenced — by the
##      thing it was a proxy for: every machine must be UNIQUELY ADDRESSABLE.
##      LineFlow now mints a per-instance key, so the run asserts that every
##      machine_list() row carries a distinct non-empty key AND that
##      get_machine_info(key) comes back describing THAT NODE — identity, not
##      merely a non-empty dict, because non-emptiness is the vacuous version and
##      the old first-match resolver would have satisfied it.
##      The collision census itself is KEPT and still printed: 14 duplicate ids on
##      Line 3A is now a true and harmless fact (an id is a machine TYPE), and
##      losing the number would lose the ability to notice it changing.
##  (c) THE CALIBRATED AMPS PATH. Also rewritten. It used to record a dead path:
##      l3c_code stamped on 0 of 47 nodes, sum(amps_nominal) 0.00 A against
##      ProcessModel.line_nominal_amps() 488.49 A, so every non-zero current in
##      the sim came from MotorOverload's PLACEHOLDER 90 A default instead.
##      Now asserted BOTH WAYS, because only the pair is meaningful:
##        * every line_3c stage carries its code, and sum(amps_nominal) over the
##          coded nodes equals ProcessModel.line_nominal_amps() exactly;
##        * NO machine outside the line_3c macro carries a 3C code. Line 3A
##          re-uses the same placeable ids for different equipment — its
##          frictiescheider is NOT L3C.4L — and stamping by id would both invent
##          an equipment identity and re-route the 3A chain onto the
##          Line3CDef.LINKS graph (LineFlow.gd:1029-1039).
##      The per-instance currents themselves are measured in
##      src/tests/test_line3c_identity.gd.
##
## ANTI-VACUITY GUARDS (this project's recurring failure is the green that proves
## nothing — npc-05 printed 31/31 while moving zero kg):
##  * amps == 0.0 would be trivially true on a stopped line, so the line is
##    STARTED and spin-up is driven to completion; spinning_count is asserted > 0
##    and reported. ProcessModel.stage_amps returns 0 when `running` is false.
##  * stage_amps itself is exercised with a known non-zero nominal, so a 0.0 line
##    current is attributable to amps_nominal and not to a dead formula.
##  * collisions are measured off the live LineFlow node set AND cross-checked
##    against a static parse of BuildMode.LINE_3A_SEQ, and the two are ASSERTED
##    equal. A collision count also needs a world to exist, so machine_nodes > 0
##    and macro_nodes > 0 are separate checks — 0 nodes yields 0 collisions too.
##  * the line is FED, not just powered. See _drive_line.
##  * the two waterflow rows are `water_add x thru`, so both read 0.0 whenever
##    nothing flows — a run alone cannot tell "no water modelled here" from
##    "nothing was moving". water_add is therefore measured per profile directly.
##
## user:// SAFETY: every file this test can touch is byte-backed-up and restored.
## The operator's allernieuwste_* saves are additionally hash-checked before and
## after — this test must never write them, and now proves it.

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")
const ProcessModelScript = preload("res://src/sim/ProcessModel.gd")
const TagMapScript = preload("res://src/sim/TagMap.gd")

# ── Building frame (bf) — the same fitted frame regression_world_save.gd uses,
# so both tests build in one frame.
# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")

const TEST_SLOT := "__tagsnap__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__tagsnap___save.json", "user://__tagsnap___factory.json",
]
const DUMP_PATH := "user://tag_snapshot.json"

const MACRO_ID := "line_3a"
const LINE_START_BF := Vector2(4.0, 22.0)

## The Line 3C spine. Every machine it places carries an l3c_code derived from its
## macro_index, so the map can be resolved per UNIT instead of per placeable id.
## It also supplies the tail stage the lines/3c/data/throughputactual row cites
## (Line3CDef.tail_code() 'Voorraad' -> voorraad_silo). Before this macro existed
## the singleton 3C ids had to be dropped into the world loose, and the L/R units
## could not be addressed at all.
const MACRO_3C := "line_3c"
# bf(4,62) put line 3C on the hall edge: 9 of its 37 machines outside the
# shell even in the fitted frame (measured 2026-09-25). bf(4,44) keeps it
# 37/37 under the roof beside line 3A at bf(4,22), no footprint overlap.
const LINE_3C_START_BF := Vector2(4.0, 44.0)

# Sim time driven after start_line(): PLCSequencer's whole-line power-up is capped
# near TARGET_STARTUP_S = 20 s (LineFlow.gd:51) and each machine then ramps over
# SPIN_UP_S = 2.5 s, so 40 s guarantees every stage is spinning.
const TICK_DT := 0.1
const TICK_COUNT := 400

# Feed stimulus, copied from the production feed path so the sample the machines
# receive is the SAME shape a real bale delivers (LineFlow.gd:30,40,1887-1893).
const FEED_RATE := 8.0
const FEED_DENSITY := 320.0
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}

var _pass := 0
var _fail := 0
var _skip := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _guarded : Dictionary = {}
var _dump : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1

func _note(msg: String) -> void:
	print("  note  : %s" % msg)

func _section(t: String) -> void:
	print("\n[%s]" % t)



func _ready() -> void:
	print("=== TAG SNAPSHOT — TagMap x real MainWorld (measured) ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via a .tscn, not --script)")
		get_tree().quit(2); return

	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return
	_guard_operator_saves()

	# ── TagMap alone first: an invented tag name must fail before a world boots.
	var tm : TagMap = TagMapScript.new()
	_test_tagmap(tm)

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	var lf = world.get("line_flow")
	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if lf == null or bm == null:
		print("FATAL: LineFlow (%s) or BuildMode (%s) missing after boot"
			% [str(lf != null), str(bm != null)])
		_finish(world); return

	await _build_world(bm, lf)
	_drive_line(lf)
	_snapshot(tm, lf, bm)

	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])
	_verify_operator_saves()
	_write_dump()
	_finish(world)


## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish(world: Node = null) -> void:
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	if world != null and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _test_tagmap(tm: TagMap) -> void:
	_section("TAGMAP — the map itself, against the operator's export")
	var v : Dictionary = tm.validation()
	v["missing_from_export"] = Array(v["missing_from_export"])
	_dump["tagmap_validation"] = v
	_ok(String(v["load_error"]) == "",
		"export loaded (%d tags from %s)" % [int(v["export_tags"]), TagMapScript.EXPORT_PATH])
	_ok((v["missing_from_export"] as Array).is_empty(),
		"EVERY mapped tag string is verbatim in the export (%d absent: %s)"
			% [(v["missing_from_export"] as Array).size(), str(v["missing_from_export"])])
	_ok(int(v["mapped_tags"]) == int(v["expected_rows"]),
		"row count %d == EXPECTED_ROWS %d" % [int(v["mapped_tags"]), int(v["expected_rows"])])
	_ok(bool(v["ok"]), "TagMap.validation().ok")
	# Every row must carry a cite on BOTH sides — no-build-without-docs is data
	# here, not a comment that can drift away from the table.
	var uncited := 0
	for r in tm.rows():
		var c := String(r["cite"])
		if c.find("TAG ") < 0 or c.find("SIM ") < 0:
			uncited += 1
	_ok(uncited == 0, "every row cites BOTH the tag source and the sim source (%d uncited)" % uncited)
	print("        confidence: %s ; coverage %.1f %% of %d exported tags"
		% [str(v["by_confidence"]), float(v["coverage_pct"]), int(v["export_tags"])])


# =============================================================================
## Place one macro from its CLEAN const seed. In-memory cache clear only — the
## on-disk operator macro is untouched (regression_world_save.gd uses the same trick).
func _place_macro(bm, macro_id: String, start_bf: Vector2) -> void:
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[macro_id] = {}
	var fr : Dictionary = await BFrame.wait_fitted(bm)
	_ok(not fr.is_empty(), "%s: building frame FITTED from the shell (InteriorLightingManager)" % macro_id)
	if fr.is_empty():
		return
	var start : Vector3 = BFrame.to_scene(fr, start_bf, Plant.floor_top_y())
	bm.call("_build_full_line", macro_id, start, BFrame.forward_rot_y(fr))
	for _i in range(10):
		await get_tree().process_frame


func _build_world(bm, lf) -> void:
	_section("WORLD — the line_3c spine (the map's own line) + line_3a alongside it")
	await _place_macro(bm, MACRO_3C, LINE_3C_START_BF)
	# Line 3A re-uses the same placeable ids for DIFFERENT plant equipment. It is
	# built here on purpose: it is what makes the collision census below non-zero,
	# and it is the trap any id-keyed resolution falls into.
	await _place_macro(bm, MACRO_ID, LINE_START_BF)

	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame
	var codes_live : Dictionary = {}
	for e in (lf.call("machine_list") as Array):
		var c := String((e as Dictionary).get("l3c_code", ""))
		if c != "":
			codes_live[c] = true
	_ok(codes_live.size() == Line3CDefScript.stage_count(),
		"the 3C spine is live: %d stage codes addressable, Line3CDef has %d"
			% [codes_live.size(), Line3CDefScript.stage_count()])
	_dump["world"] = {
		"save_slot": TEST_SLOT,
		"macros_built": [MACRO_3C, MACRO_ID],
		"codes_live": codes_live.size(),
	}


# =============================================================================
## Start the line, FEED it, and drive sim time forward with a FIXED delta.
##
## The feed is not decoration. Without material the whole flow half of the map
## (thru, buffer, the two waterflow rows, throughputactual, productioncounter)
## reads 0.0 no matter what the sim does — a line that is "Running" while moving
## zero kg is precisely the npc-05 failure shape, and every one of those rows
## would then be satisfied by a stub. The production feed path (LineFlow.gd:1874-1900)
## needs a physical bale parked on the head's feed point, which a headless world
## has none of, so this mirrors that path exactly: same head selection (no
## incoming edge, not a sink), same FEED_RATE, same wet+dirty sample shape as
## LineFlow.gd:1892-1893. Material then travels the REAL machine pipeline.
func _drive_line(lf) -> void:
	_section("RUN — power the line, FEED it, complete PLC stagger + rotor spin-up")
	lf.call("start_line")
	var injected := 0.0
	for _i in range(TICK_COUNT):
		injected += _feed_heads(lf, TICK_DT)
		lf.call("tick", TICK_DT)
	var fed : float = float(lf.get("fed_mass"))
	print("        drove %.1f s of sim time in %d fixed ticks ; injected %.1f kg at the heads (LineFlow.fed_mass stays %.1f kg — that counter belongs to the bale path at LineFlow.gd:1895, which did not run)"
		% [TICK_DT * float(TICK_COUNT), TICK_COUNT, injected, fed])
	_dump["feed"] = {
		"injected_kg": injected,
		"line_flow_fed_mass_kg": fed,
		"feed_rate_kg_s": FEED_RATE,
		"why": "LineFlow's own feed loop (LineFlow.gd:1874-1900) needs a physical bale on the head feed point; a headless world has none, so the head 'in' batches are charged directly with the same sample shape as LineFlow.gd:1892-1893",
		"caveat": "EVERY head is charged at FEED_RATE, and a 47-machine world has several heads, so lines/3c/data/throughputactual comes out well above Line3CDef.LINE_SPEED_KG_H. This stimulus exists to prove the flow rows are LIVE, not to calibrate them — no throughput figure from this run is a plant number.",
		"fed_mass_note": "LineFlow.fed_mass is deliberately NOT used as the pass criterion; it is incremented only inside the bale branch (LineFlow.gd:1895) and would read 0 here even though material demonstrably moved.",
	}
	_ok(injected > 0.0,
		"FEED: %.1f kg injected at the line heads — the flow half of the map is exercised, not left at 0" % injected)


## Mirror of the production feed loop's head selection + sample construction.
func _feed_heads(lf, delta: float) -> float:
	var nodes : Array = lf.get("_nodes")
	var fed := 0.0
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd["role"]) == "sink":
			continue
		if bool(lf.call("_has_incoming", i)):
			continue
		var draw : float = FEED_RATE * delta
		(nd["in"] as MaterialBatch).add(MaterialBatch.new(
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "tagsnap_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


# =============================================================================
func _snapshot(tm: TagMap, lf, bm) -> void:
	_section("SNAPSHOT — machine_list() -> get_machine_info() -> TagMap")

	var nodes : Array = lf.get("_nodes")
	var listed : Array = lf.call("machine_list")

	# ── addressability, MEASURED off the live node set ─────────────────────────
	var seen : Dictionary = {}
	for e in listed:
		var mid := String((e as Dictionary).get("id", ""))
		seen[mid] = int(seen.get(mid, 0)) + 1
	var dup_breakdown : Dictionary = {}
	for k in seen.keys():
		if int(seen[k]) > 1:
			dup_breakdown[k] = int(seen[k])
	var collisions : int = listed.size() - seen.size()

	# Same figure restricted to the macro's own machines, which is what the design
	# doc's "~14 on Line 3A" prediction is about.
	var macro_ids : Dictionary = {}
	var macro_total := 0
	for nd in nodes:
		var n = (nd as Dictionary).get("node", null)
		if n == null or not is_instance_valid(n):
			continue
		if not (n as Node).has_meta("macro_id"):
			continue
		if String((n as Node).get_meta("macro_id")) != MACRO_ID:
			continue
		macro_total += 1
		var mid2 := String((nd as Dictionary).get("id", ""))
		macro_ids[mid2] = int(macro_ids.get(mid2, 0)) + 1
	var macro_collisions : int = macro_total - macro_ids.size()

	# Static cross-check of the same defect over the shipped macro seed, so the
	# live figure cannot silently drift away from the source of truth.
	var seq_ids : Dictionary = {}
	var seq_total := 0
	for entry in BuildMode.LINE_3A_SEQ:
		var sid := String((entry as Dictionary).get("id", ""))
		if sid == "":
			continue
		seq_total += 1
		seq_ids[sid] = int(seq_ids.get(sid, 0)) + 1
	# The 20 SCADA-aligned Line 3C units collapse onto how many distinct ids?
	var l3c_units := 0
	var l3c_ids : Dictionary = {}
	for st in Line3CDefScript.STAGES:
		var code := String((st as Dictionary)["code"])
		if not code.begins_with("L3C."):
			continue
		l3c_units += 1
		l3c_ids[String((st as Dictionary)["id"])] = true

	var addressability : Dictionary = {
		"machine_nodes": listed.size(),
		"distinct_ids": seen.size(),
		"duplicate_id_collisions": collisions,
		"duplicate_breakdown": dup_breakdown,
		"macro_id": MACRO_ID,
		"macro_nodes": macro_total,
		"macro_distinct_ids": macro_ids.size(),
		"macro_collisions": macro_collisions,
		"static_LINE_3A_SEQ_entries": seq_total,
		"static_LINE_3A_SEQ_distinct": seq_ids.size(),
		"static_LINE_3A_SEQ_collisions": seq_total - seq_ids.size(),
		"scada_aligned_l3c_units": l3c_units,
		"scada_aligned_distinct_ids": l3c_ids.size(),
		"scada_aligned_ids_shared_by": l3c_units - l3c_ids.size(),
		"note": "duplicate ids are NORMAL and harmless — a placeable id is a machine TYPE. What used to make them a defect was LineFlow having no other handle; every node now carries a distinct key (nd[\"key\"]), asserted below.",
	}
	_dump["addressability"] = addressability

	# ── amps: the lie this snapshot exists to put a number on ─────────────────
	var powered := 0
	var spinning := 0
	var amps_nominal_sum := 0.0
	var stamped := 0
	# ATTRIBUTION: nd["amps"] has more than one writer. Record every node that
	# reads non-zero and where its number came from, so a non-zero line current
	# can be explained instead of merely noticed.
	var amps_by_node : Array = []
	var mol_nodes := 0
	# Machines a MotorOverload has TRIPPED. LineFlow.gd:2269-2270 forces
	# powered = false on a trip, so a tripped drive legitimately reports
	# em/status == false and the status census below must account for it by name
	# rather than being loosened to a threshold.
	var tripped_ids : Dictionary = {}
	for nd2 in nodes:
		var d : Dictionary = nd2
		var mol_t = d.get("mol", null)
		if mol_t != null and bool(mol_t.call("is_tripped")):
			tripped_ids[String(d.get("id", ""))] = true
		if bool(d.get("powered", false)):
			powered += 1
		if float(d.get("spin", 0.0)) > 0.1:
			spinning += 1
		amps_nominal_sum += float(d.get("amps_nominal", 0.0))
		if String(d.get("l3c_code", "")) != "":
			stamped += 1
		var mol = d.get("mol", null)
		if mol != null:
			mol_nodes += 1
		var a : float = float(d.get("amps", 0.0))
		if a > 0.0:
			amps_by_node.append({
				"id": String(d.get("id", "")),
				"amps": a,
				"amps_nominal_from_l3c": float(d.get("amps_nominal", 0.0)),
				"has_motor_overload": mol != null,
				"mol_nominal_amps": float(mol.get("nominal_amps")) if mol != null else 0.0,
				"mol_idle_frac": float(mol.get("idle_frac")) if mol != null else 0.0,
			})
	var live_amps : float = float(lf.call("live_line_amps"))
	# Formula sanity: a KNOWN non-zero nominal at idle load must produce current.
	# Without this, "0.0 A" could equally mean stage_amps is broken.
	var probe_amps : float = ProcessModelScript.stage_amps(29.92, 0.0, true)
	var nominal_line : float = ProcessModelScript.line_nominal_amps()
	var amps_block : Dictionary = {
		"live_line_amps": live_amps,
		"machines_powered": powered,
		"machines_spinning": spinning,
		"sum_amps_nominal_over_nodes": amps_nominal_sum,
		"nodes_with_l3c_code_stamped": stamped,
		"process_model_line_nominal_amps": nominal_line,
		"stage_amps_probe_29_92A_idle_running": probe_amps,
		"nodes_with_motor_overload": mol_nodes,
		"nodes_with_nonzero_amps": amps_by_node,
		"was_before_the_fix": "l3c_code stamped on 0 of 47 nodes and sum(amps_nominal) 0.00 A against the same 488.49 A line nominal — the only set_meta(\"l3c_code\") call site repo-wide was a bench (tests/FlakeCouplingTest.gd:64), so LineFlow.gd:474-482 never ran in production and every current came from a placeholder",
		"run_stability": "live_line_amps is NOT run-stable once the line is fed: MotorOverload.current_amps on a LOADED drive tracks accumulated backlog, which moves with physics/nav timing. Treat it as a magnitude, never as a fixture value. The EXACT invariants — and the ones asserted — are nodes_with_l3c_code_stamped == Line3CDef.stage_count() and sum_amps_nominal_over_nodes == process_model_line_nominal_amps.",
		"second_writer": "MotorOverload OVERWRITES nd[\"amps\"] every tick (LineFlow.gd:2269-2275) with its own current_amps. It is now SEEDED from the stage's own amps_nominal, so on a coded stage that number is calibrated rather than the 90.0 A default; an UNCODED high-load drive (Line 3A/3B/1) still falls back to that default, which is why only a line_3c world reports calibrated currents",
	}
	_dump["amps"] = amps_block

	# ── resolve every mapped tag ───────────────────────────────────────────────
	var machine_ctx : Dictionary = {
		"estop_fault_id": String(lf.call("estop_fault_id")),
		# Per-INSTANCE fault identity: estop_fault_id names a machine TYPE and
		# would light the em/alarm row of all five friction separators at once.
		"estop_fault_key": String(lf.call("estop_fault_key")),
	}
	var line_status := "Idle"
	if bool(lf.call("is_estopped")):
		line_status = "Fault"
	elif bool(lf.call("is_line_starting")):
		line_status = "Starting"
	elif float(lf.call("line_powered_fraction")) > 0.0:
		line_status = "Running"
	var line_ctx : Dictionary = {"line_status": line_status, "gran_mass_kg": float(lf.get("gran_mass"))}
	# The tail stage, addressed by its CODE — the sim's throughput has to come from
	# the 3C line's own last machine, not from whichever voorraad_silo answers first.
	var tail_info : Dictionary = lf.call("get_machine_info", Line3CDefScript.tail_code())
	if not tail_info.is_empty():
		line_ctx["tail_thru_kg_h"] = float(tail_info["thru"]) * 3600.0
	var ctx_missing : Array = []
	for k2 in TagMapScript.LINE_CTX_KEYS:
		if not line_ctx.has(String(k2)):
			ctx_missing.append(String(k2))

	# Resolve ONE UNIT at a time, addressed by its own plant code. This used to
	# iterate DISTINCT placeable ids instead, because get_machine_info could not
	# reach a second instance of an id at all — so five friction separators shared
	# one reading and ten of the twenty units had no reading. Each row now
	# describes the machine the operator's tag actually names.
	var out_rows : Array = []
	var addressed : Array = []
	for u in TagMapScript.UNITS.keys():
		addressed.append(String((TagMapScript.UNITS[String(u)] as Array)[0]))
	var resolved_codes : Dictionary = {}
	var hit_paths : Dictionary = {}
	for code_a in addressed:
		var code3 := String(code_a)
		if resolved_codes.has(code3):
			continue
		var info : Dictionary = lf.call("get_machine_info", code3)
		if info.is_empty():
			continue
		resolved_codes[code3] = true
		# WHICH machine answered? Recorded per row: a map that cannot say which
		# machine it read is not instance-truthful, and this is the field that
		# would expose a silent fallback to first-match-by-id.
		var hit_path := ""
		var hit_id := ""
		for nd3 in nodes:
			if String((nd3 as Dictionary).get("key", "")) == String(info.get("key", "")):
				var hn = (nd3 as Dictionary).get("node", null)
				if hn != null and is_instance_valid(hn):
					hit_path = String((hn as Node).get_path())
				hit_id = String((nd3 as Dictionary).get("id", ""))
				break
		hit_paths[code3] = hit_path
		for r in tm.resolve_code(code3, info, machine_ctx):
			var row : Dictionary = r
			row["resolved_instance_path"] = hit_path
			row["resolved_machine_key"] = String(info.get("key", ""))
			row["instances_of_this_id"] = int(seen.get(hit_id, 0))
			out_rows.append(row)
	for lr in tm.resolve_line(line_ctx):
		out_rows.append(lr)

	# Mapped units that simply are not in this world -> their rows are absent, and
	# that absence is reported rather than papered over.
	var absent_ids : Array = []
	for a in addressed:
		if not resolved_codes.has(String(a)):
			absent_ids.append(String(a))

	var resolved_tags := 0
	var unresolved : Array = []
	# LIVENESS census. A resolved row proves only that a KEY existed; it does not
	# prove the sim produced anything. Counted separately so a world of all-default
	# values cannot masquerade as a live one (mutation-tested: an all-zero /
	# all-false get_machine_info makes every one of these figures collapse).
	var n_bool := 0
	var n_bool_true := 0
	var n_num := 0
	var n_num_nonzero := 0
	var distinct_num : Dictionary = {}
	var status_rows := 0
	var status_true := 0
	var status_false_tripped : Array = []
	var status_false_unexplained : Array = []
	# A tripped drive's em/alarm row: does the map SEE the trip? Measured, because
	# the row binds to estop_fault_id() only — MotorOverload has no public accessor.
	var alarm_on_tripped : Array = []
	var speed_rows := 0
	var speed_positive := 0
	var flow_rows := 0
	var flow_positive := 0
	for row2 in out_rows:
		var rr : Dictionary = row2
		if not bool(rr["resolved"]):
			unresolved.append(String(rr["tag"]))
			continue
		resolved_tags += 1
		var v = rr["value"]
		var tg := String(rr["tag"])
		if v is bool:
			n_bool += 1
			if bool(v):
				n_bool_true += 1
		elif v is float or v is int:
			n_num += 1
			if not is_equal_approx(float(v), 0.0):
				n_num_nonzero += 1
			distinct_num[snappedf(float(v), 0.001)] = true
		if tg.ends_with("/em/status"):
			status_rows += 1
			if bool(v):
				status_true += 1
			elif tripped_ids.has(String(rr["machine_key"])):
				status_false_tripped.append("%s (%s)" % [tg, String(rr["machine_key"])])
			else:
				status_false_unexplained.append("%s (%s)" % [tg, String(rr["machine_key"])])
		elif tg.ends_with("/em/alarm"):
			if tripped_ids.has(String(rr["machine_key"])):
				alarm_on_tripped.append({
					"tag": tg, "machine": String(rr["machine_key"]),
					"alarm_row_reads": bool(v),
					"motor_overload_tripped": true,
				})
		if tg.ends_with("/em/snelheid"):
			speed_rows += 1
			if float(v) > 0.0:
				speed_positive += 1
		# Rows that can only be non-zero if MATERIAL ACTUALLY MOVED.
		if tg.ends_with("/niveau") or tg.ends_with("waterflow") \
				or tg == "lines/3c/data/throughputactual" or tg == "lines/3c/data/productioncounter":
			flow_rows += 1
			if float(v) > 0.0:
				flow_positive += 1

	# ── waterflow ATTRIBUTION, measured statically ────────────────────────────
	# The two waterflow rows are `water_add x thru`. Both read 0.0 on an unfed
	# line, so a run cannot tell "no water is modelled here" from "nothing was
	# flowing". The per-machine water_add is therefore measured directly, which is
	# the actual defect: MachineFlow.profile() is an EXACT `match id:`
	# (MachineFlow.gd:28,51) whose float arm names "flotation_tank" and
	# "sink_float" (MachineFlow.gd:381-385) but NOT "flotation_tank_wide" — the id
	# Line3CDef.gd:65 gives L3C.11 — so the sim's Flotatietank silently takes the
	# generic profile (MachineFlow.gd:29-50, water_add 0.0).
	var wf : Dictionary = {}
	for wid in ["sink_float", "flotation_tank", "flotation_tank_wide"]:
		var prof : Dictionary = MachineFlow.profile(String(wid))
		wf[wid] = {"water_add": float(prof.get("water_add", 0.0)), "process": String(prof.get("process", ""))}
	_dump["waterflow_attribution"] = wf

	_dump["resolution"] = {
		"mapped_tags": tm.rows().size(),
		"emitted_rows": out_rows.size(),
		"resolved_tags": resolved_tags,
		"unresolved_tags": unresolved.size(),
		"unresolved": unresolved,
		"liveness": {
			"bool_rows": n_bool, "bool_rows_true": n_bool_true,
			"numeric_rows": n_num, "numeric_rows_nonzero": n_num_nonzero,
			"distinct_numeric_values": distinct_num.size(),
			"em_status_rows": status_rows, "em_status_true": status_true,
			"em_status_false_tripped": status_false_tripped,
			"em_status_false_unexplained": status_false_unexplained,
			"tripped_machine_ids": tripped_ids.keys(),
			"em_snelheid_rows": speed_rows, "em_snelheid_positive": speed_positive,
			"material_flow_rows": flow_rows, "material_flow_positive": flow_positive,
		},
		"mapped_l3c_units": addressed,
		"l3c_units_present": resolved_codes.keys(),
		"l3c_units_absent_from_world": absent_ids,
		"resolved_instance_paths": hit_paths,
		"line_ctx": line_ctx,
		"line_ctx_missing": ctx_missing,
		"machine_ctx": machine_ctx,
	}
	_dump["tags"] = out_rows
	_dump["meta"] = {
		"generated_by": "src/tests/test_tag_snapshot.gd",
		"design_doc": "docs/DESIGN_hmi_tag_bridge_2026-07-22.md §8",
		"read_only": true,
		"sim_seconds_driven": TICK_DT * float(TICK_COUNT),
		"build_mode_present": bm != null,
	}

	# ── the three pass criteria ────────────────────────────────────────────────
	_section("PASS CRITERIA (§8) — measured, not asserted")
	# (a) STRENGTHENED after an adversarial review of this very file. The original
	#     pair was `resolved_tags > 0` + `null_valued == 0`, and BOTH were vacuous:
	#       * null_valued was a TAUTOLOGY — _emit() defines resolved := value != null,
	#         so a null value can never be counted as resolved. It printed "0 null"
	#         even with an EMPTY map.
	#       * resolved_tags > 0 survived get_machine_info() being stubbed to {} —
	#         73 of 77 rows went unresolved and the run still printed PASS, because
	#         the 4 line-level rows alone cleared "> 0".
	#     Replaced with the exact counts, so either mutation now goes RED.
	_ok(absent_ids.is_empty(),
		"(a) every mapped L3C unit is present in this world AND answered to its own code (%d absent: %s)"
			% [absent_ids.size(), str(absent_ids)])
	_ok(out_rows.size() == tm.rows().size(),
		"(a) every mapped row was emitted: %d emitted == %d mapped" % [out_rows.size(), tm.rows().size()])
	_ok(unresolved.is_empty(),
		"(a) ZERO unresolved rows — every row got a value from get_machine_info/line ctx (%d unresolved: %s)"
			% [unresolved.size(), str(unresolved).substr(0, 200)])
	_ok(resolved_tags == tm.rows().size(),
		"(a) resolved_tags == mapped_tags: %d == %d" % [resolved_tags, tm.rows().size()])
	# (a2) LIVENESS — the guard the original criteria lacked entirely. A
	#      get_machine_info() returning every correct KEY with every value at its
	#      type default scored an identical 12 ok / 0 fail before these landed.
	_ok(n_bool_true > 0 and n_num_nonzero > 0,
		"(a2) NOT VACUOUS: %d of %d bool rows are true and %d of %d numeric rows are non-zero — an all-default get_machine_info() would make both 0"
			% [n_bool_true, n_bool, n_num_nonzero, n_num])
	# Strict, but trip-aware BY NAME rather than by a loosened threshold: a
	# MotorOverload trip forces powered = false (LineFlow.gd:2269-2270), so that
	# machine's status row is legitimately false and must be accounted for, not
	# tolerated. Any OTHER false is a failure.
	_ok(status_rows > 0 and status_false_unexplained.is_empty(),
		"(a2) every em/status row reads TRUE after start_line + %.0f s, except %d explained by a MotorOverload trip (%d true / %d rows; unexplained false: %s)"
			% [TICK_DT * float(TICK_COUNT), status_false_tripped.size(),
				status_true, status_rows, str(status_false_unexplained)])
	if not status_false_tripped.is_empty():
		_note("(a2) tripped drives, status legitimately false: %s ; tripped ids: %s"
			% [str(status_false_tripped), str(tripped_ids.keys())])
	# MEASURED, not asserted: does the mapped em/alarm row see a real trip? The map
	# binds it to estop_fault_id() alone because MotorOverload has no public
	# accessor, so the expectation is that it does NOT. Printed either way so the
	# gap has a number; if a later change wires the trip in, this note flips and the
	# row's "PARTIAL" confidence note in TagMap.gd must be updated with it.
	for a2 in alarm_on_tripped:
		var ad : Dictionary = a2
		if bool(ad["alarm_row_reads"]):
			_note("(a2) em/alarm row %s READS TRUE on a tripped drive — the MotorOverload half is now visible; update the row note in TagMap.gd"
				% String(ad["tag"]))
		else:
			_note("(a2) GAP MEASURED: %s reads FALSE while machine '%s' is ACTUALLY TRIPPED by MotorOverload. Confirms the row's PARTIAL note — estop_fault_id() (LineFlow.gd:1651-1654) is empty because a MOL trip is not an E-stop, and MotorOverload.is_tripped() (MotorOverload.gd:157) is reachable through no public LineFlow accessor. A real HMI would be lit here."
				% [String(ad["tag"]), String(ad["machine"])])
	_dump["alarm_gap"] = alarm_on_tripped
	_ok(speed_rows > 0 and speed_positive == speed_rows,
		"(a2) every em/snelheid row reads > 0 (%d of %d) — spin x rpm_pct x max_rpm is live"
			% [speed_positive, speed_rows])
	_ok(distinct_num.size() >= 4,
		"(a2) %d DISTINCT numeric values across the map — values are differentiated per machine/component, not one repeated constant"
			% distinct_num.size())
	_ok(flow_positive > 0,
		"(a2) MATERIAL MOVED: %d of %d flow-only rows (niveau / waterflow / throughputactual / productioncounter) are > 0 — these are 0 on a line that runs empty"
			% [flow_positive, flow_rows])
	# waterflow attribution, asserted against the static profiles so the claim in
	# TagMap's 6_11 note is measured rather than repeated.
	_ok(float((wf["sink_float"] as Dictionary)["water_add"]) > 0.0,
		"(a2) MachineFlow.profile(\"sink_float\").water_add = %.2f > 0 — unit 3's waterflow row has a real coefficient behind it"
			% float((wf["sink_float"] as Dictionary)["water_add"]))
	_ok(is_equal_approx(float((wf["flotation_tank_wide"] as Dictionary)["water_add"]), 0.0)
			and float((wf["flotation_tank"] as Dictionary)["water_add"]) > 0.0,
		"(a2) DEFECT MEASURED: water_add is %.2f for \"flotation_tank_wide\" (L3C.11's id, Line3CDef.gd:65) but %.2f for \"flotation_tank\" — the MachineFlow.gd:381-385 arm misses the _wide id, so the Flotatietank runs the generic profile (process '%s')"
			% [float((wf["flotation_tank_wide"] as Dictionary)["water_add"]),
				float((wf["flotation_tank"] as Dictionary)["water_add"]),
				String((wf["flotation_tank_wide"] as Dictionary)["process"])])
	# (b) The world must really have been built before any of this means anything
	#     — 0 nodes yields 0 collisions AND 0 addressing failures. This guard is
	#     load-bearing and is kept VERBATIM from the version that measured the
	#     defect; without it the rewritten criterion passes on an empty world.
	_ok(listed.size() > 0 and macro_total > 0,
		"(b) a real world was built: %d LineFlow machines, %d of them from macro '%s'"
			% [listed.size(), macro_total, MACRO_ID])
	# (b) UNIQUE ADDRESSABILITY — the rewrite of the old `collisions != 0` line.
	#     Two assertions, because either alone is satisfiable by a fake:
	#       1. distinct non-empty keys, one per node. A constant key collapses this.
	#       2. get_machine_info(key) returns THAT node. A resolver that ignored the
	#          key and first-matched the id would still return a non-empty dict for
	#          every row, so non-emptiness proves nothing — the scene path of the
	#          machine that answered is compared against the row's own node.
	var blank_keys := 0
	var key_set : Dictionary = {}
	for e_k in listed:
		var kk := String((e_k as Dictionary).get("key", ""))
		if kk == "":
			blank_keys += 1
		key_set[kk] = true
	_ok(blank_keys == 0 and key_set.size() == listed.size(),
		"(b) every one of %d machines has a DISTINCT non-empty key (%d distinct, %d blank) — an id alone cannot address a machine, %d of these nodes share one"
			% [listed.size(), key_set.size(), blank_keys, collisions])
	var mis_resolved : Array = []
	for ni in nodes.size():
		var nd_i : Dictionary = nodes[ni]
		var own_node = nd_i.get("node", null)
		if own_node == null or not is_instance_valid(own_node):
			continue
		var own_path := String((own_node as Node).get_path())
		var info_i : Dictionary = lf.call("get_machine_info", String(nd_i.get("key", "")))
		# Resolve the SAME key a second time through the node set to recover the
		# path the resolver actually reached.
		var hit := ""
		for nd_j in nodes:
			if String((nd_j as Dictionary).get("key", "")) == String(info_i.get("key", "")):
				var hj = (nd_j as Dictionary).get("node", null)
				if hj != null and is_instance_valid(hj):
					hit = String((hj as Node).get_path())
				break
		if info_i.is_empty() or hit != own_path:
			mis_resolved.append("%s -> %s (wanted %s)" % [String(nd_i.get("key", "")), hit, own_path])
	_ok(mis_resolved.is_empty(),
		"(b) get_machine_info(key) resolves to THAT MACHINE for all %d nodes — identity, not just a non-empty dict (%d wrong: %s)"
			% [nodes.size(), mis_resolved.size(), str(mis_resolved).substr(0, 240)])
	_ok((lf.call("code_conflicts") as Array).is_empty(),
		"(b) no l3c_code was claimed by two nodes (%d conflict(s): %s)"
			% [(lf.call("code_conflicts") as Array).size(), str(lf.call("code_conflicts"))])
	_ok(macro_collisions == seq_total - seq_ids.size(),
		"(b) live macro collisions %d == static BuildMode.LINE_3A_SEQ collisions %d — the live figure and the shipped seed agree"
			% [macro_collisions, seq_total - seq_ids.size()])
	print("        (b) %s subset: %d collisions (%d nodes / %d distinct) ; static LINE_3A_SEQ: %d (%d/%d) ; the %d SCADA-aligned 3C units share only %d distinct ids — normal now that an id is a TYPE, fatal when it was the only handle"
		% [MACRO_ID, macro_collisions, macro_total, macro_ids.size(),
			seq_total - seq_ids.size(), seq_total, seq_ids.size(),
			l3c_units, l3c_ids.size()])
	print("        (b) duplicates: %s" % str(dup_breakdown))
	# (c) is a MEASUREMENT, printed prediction-next-to-actual. Only its vacuity
	# guards gate the verdict — the number itself is reported however it comes out.
	print("        (c) live_line_amps MEASURED %.4f A  (not run-stable once fed — see the dump's run_stability note; the EXACT invariants are asserted below)" % live_amps)
	print("        (c) machines powered %d / spinning %d ; sum(amps_nominal) %.2f A ; l3c_code stamped on %d nodes"
		% [powered, spinning, amps_nominal_sum, stamped])
	print("        (c) ProcessModel.line_nominal_amps() %.2f A -> %.2f A at idle load, %.2f A at full load"
		% [nominal_line, nominal_line * ProcessModelScript.MOTOR_IDLE_FRAC, nominal_line])
	print("        (c) nd[\"amps\"] non-zero on %d of %d nodes (%d carry a MotorOverload): %s"
		% [amps_by_node.size(), nodes.size(), mol_nodes, str(amps_by_node)])
	_ok(spinning > 0,
		"(c) NOT VACUOUS: %d machines are spinning, so stage_amps ran with running == true" % spinning)
	_ok(probe_amps > 0.0,
		"(c) NOT VACUOUS: stage_amps(29.92 A, load 0, running) = %.2f A > 0 — the formula is alive" % probe_amps)
	# (c) NO 3A MACHINE MAY ACQUIRE A 3C ADDRESS. The code is DERIVED from macro
	# membership and only the line_3c macro resolves, so a Line 3A frictiescheider
	# (BuildMode.gd:98-106, cited to water_circuit_3a_la1.md) stays uncoded. This is
	# the guard against the cheap way to make the amps numbers appear: stamping 3C
	# codes onto whatever machine happens to share the placeable id. Doing that
	# would ALSO re-route the whole 3A chain onto the Line3CDef.LINKS graph
	# (LineFlow.gd:1029-1039) and swap its material balance (:474-481).
	var wrongly_coded : Array = []
	for nd_c in nodes:
		var n_c = (nd_c as Dictionary).get("node", null)
		if n_c == null or not is_instance_valid(n_c) or not (n_c as Node).has_meta("macro_id"):
			continue
		if String((n_c as Node).get_meta("macro_id")) == "line_3c":
			continue
		if String((nd_c as Dictionary).get("l3c_code", "")) != "":
			wrongly_coded.append("%s (%s) -> %s" % [String((nd_c as Dictionary)["id"]),
				String((n_c as Node).get_meta("macro_id")), String((nd_c as Dictionary)["l3c_code"])])
	_ok(wrongly_coded.is_empty(),
		"(c) NO machine outside the line_3c macro carries an L3C code (%d do: %s) — a Line 3A frictiescheider is not L3C.4L"
			% [wrongly_coded.size(), str(wrongly_coded)])
	_ok(stamped == Line3CDefScript.stage_count(),
		"(c) l3c_code stamped on %d nodes == Line3CDef.stage_count() %d — it was stamped NOWHERE in production before, so the calibrated path was dead"
			% [stamped, Line3CDefScript.stage_count()])
	_ok(absf(amps_nominal_sum - nominal_line) <= 0.01,
		"(c) sum(amps_nominal) %.2f A == ProcessModel.line_nominal_amps() %.2f A — it was 0.00 A against the same 488.49 A before"
			% [amps_nominal_sum, nominal_line])
	print("  note  : (c) live_line_amps = %.4f A ; %d node(s) read a non-zero current, %d of them through a MotorOverload now seeded from its own stage nominal instead of the 90.0 A placeholder (LineFlow.gd:678-680)."
		% [live_amps, amps_by_node.size(), mol_nodes])
	if not ctx_missing.is_empty():
		_note("line context incomplete: %s -> those rows resolve to null by design" % str(ctx_missing))
	if not absent_ids.is_empty():
		_note("mapped L3C units not in this world: %s" % str(absent_ids))


# =============================================================================
# user:// file safety
# =============================================================================
## The operator's live saves. Hard rule: this test must never write them. Hash
## before, verify after — a rule nobody measures is a rule nobody keeps.
func _guard_operator_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if not (fn.begins_with("allernieuwste_") and fn.ends_with(".json")):
			continue
		var f := FileAccess.open("user://" + fn, FileAccess.READ)
		if f:
			_guarded["user://" + fn] = f.get_as_text().sha256_text()
			f.close()

func _verify_operator_saves() -> void:
	var changed : Array = []
	for p in _guarded.keys():
		var f := FileAccess.open(p, FileAccess.READ)
		var h := f.get_as_text().sha256_text() if f else "<gone>"
		if f: f.close()
		if h != String(_guarded[p]):
			changed.append(p)
	if _guarded.is_empty():
		_note("no allernieuwste_*.json present to guard")
		_skip += 1
	else:
		_ok(changed.is_empty(), "operator allernieuwste_* saves byte-identical after the run (%d changed: %s)"
			% [changed.size(), str(changed)])

func _write_dump() -> void:
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dump, "  "))
		f.close()
