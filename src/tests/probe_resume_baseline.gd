extends Node
## PROBE (measures, gates nothing) — what of a RUNNING plant survives a
## save → load round trip?
##
##   APPDATA=<scratch dir> godot --headless --path . res://src/tests/probe_resume_baseline.tscn
##
## RUN IT UNDER A SCRATCH APPDATA. It calls BuildMode._save_layout(), which
## writes the factory file; both the factory file and WorldLayout's path are
## redirected to probe-only names as a second line of defence.
##
## Why: the operator (2026-09-25) wants a loaded save to be "as it was at the
## end of the shift before". The 2026-07-08 cold-start decision
## (MainWorld._spawn_world_items) says nothing of the running state is saved.
## This builds line 3B, starts the line and the extruder through their own
## controls, changes three operator settings (rpm setpoint, one zone setpoint,
## one machine in HAND at 70 %), feeds it for 60 s, and prints the same summary
## before the save and after a fresh BuildMode + LineFlow load the file, then
## after PlantResume puts the saved state back (2026-09-25). Measured before that
## existed: AFTER LOAD was the end of the story — 0 powered, extruder OFF, 60 rpm.

const FACTORY_PATH : String = "user://__resume_probe_factory.json"
const WORLD_PATH   : String = "user://__resume_probe_world_layout.json"
const RUN_S : float = 60.0
const FEED_KG_H : float = 950.0

var _t0 : int = 0
var _done : bool = false

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > 240000:
		_done = true
		print("Result: FAIL (probe watchdog)")
		get_tree().quit(2)

func _placed(bm: BuildMode) -> Node3D:
	return bm.get("_placed_root") as Node3D

func _find_id(bm: BuildMode, id: String) -> Node3D:
	for c in _placed(bm).get_children():
		if String(c.get_meta("placeable_id", "")) == id:
			return c as Node3D
	return null

func _summary(tag: String, bm: BuildMode, lf: LineFlow) -> void:
	var nodes : Array = lf.get("_nodes")
	var powered := 0
	var spin := 0.0
	var buf := 0.0
	var inl := 0.0
	var hand := 0
	var rpm_off := 0
	for nd in nodes:
		var d : Dictionary = nd
		if bool(d.get("powered", false)):
			powered += 1
		spin += float(d.get("spin", 0.0))
		buf += float(d.get("buffer", 0.0))
		for k in ["in", "out"]:
			var b = d.get(k, null)
			if b != null:
				inl += (b as MaterialBatch).mass_kg
		if bool(d.get("hand_mode", false)):
			hand += 1
		if not is_equal_approx(float(d.get("rpm_pct", 1.0)), 1.0):
			rpm_off += 1
	var pipe_kg := 0.0
	for e in lf.get("_edges"):
		for s in (e as Dictionary).get("pipe", []):
			pipe_kg += (s as MaterialBatch).mass_kg
	print("[%s] %d nodes: %d powered, spin sum %.2f, buffer %.1f kg, in/out %.1f kg, pipes %.1f kg, HAND %d, rpm_pct != 1: %d"
		% [tag, nodes.size(), powered, spin, buf, inl, pipe_kg, hand, rpm_off])
	print("[%s] ledger: fed %.1f kg, granulaat %.1f kg, waste %.1f kg" % [tag,
		float(lf.get("fed_mass")), float(lf.get("gran_mass")), float(lf.get("waste_mass"))])
	var ex := _find_id(bm, "extruder_3b")
	var brain : Node = ex.get_node_or_null("SimBrain") if ex != null else null
	if brain == null:
		print("[%s] extruder_3b: NO BRAIN" % tag)
		return
	var m : ExtruderModel = brain.get("model")
	print("[%s] extruder_3b: state %s, melt %.1f C, screw %.1f rpm, setpoint %.1f rpm, zones %s, pots %.2f/%.2f kg, runtime %.0f s"
		% [tag, m.get_state_name(), m.melt_temp, m.screw_rpm, m.screw_rpm_setpoint,
		str(m.zone_temp_setpoints), m.primary_pot_fill_kg, m.secondary_pot_fill_kg, m.runtime_s])
	print("[%s] start sequence: phase %d, run_cmd %s, natraject %s" % [tag,
		int(m.start_seq.phase), str(m.start_seq.run_cmd), str(m.start_seq.natraject_enabled)])

func _tick_all(bm: BuildMode, lf: LineFlow, secs: float, feed: bool) -> void:
	var ex := _find_id(bm, "extruder_3b")
	var brain : Node = ex.get_node_or_null("SimBrain") if ex != null else null
	var nodes : Array = lf.get("_nodes")
	var silo_i := -1
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == "extruder_silo":
			silo_i = i
	var kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	for t in int(secs / 0.1):
		if feed and silo_i >= 0:
			(((nodes[silo_i] as Dictionary)["in"]) as MaterialBatch).add(MaterialBatch.new(
				kg_tick, kg_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		lf.call("tick", 0.1)
		if brain != null:
			brain.call("_on_sim_tick", 0.1)

func _run() -> void:
	print("[PROBE] user dir = %s" % OS.get_user_data_dir())
	WorldLayout.layout_path_override = WORLD_PATH
	AtomicFile.delete(FACTORY_PATH)
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400.0, 1.0, 400.0)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(0.0, -0.5, 0.0)
	add_child(floor_body)

	var bm1 := BuildMode.new()
	bm1.layout_path = FACTORY_PATH
	bm1.load_shared_structure = false
	bm1.allow_legacy_fallback = false
	add_child(bm1)
	await get_tree().process_frame
	bm1.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var lf1 := LineFlow.new()
	add_child(lf1)
	bm1.line_flow = lf1          # MainWorld wires this (SystemsSpawner); without it no LineFlow state is saved
	await get_tree().process_frame
	lf1.call("rebuild")
	_summary("BUILT", bm1, lf1)

	# The plant's own controls: line START, the extruder's start button, and three
	# operator settings the HMI writes.
	lf1.call("start_line")
	var ex := _find_id(bm1, "extruder_3b")
	var brain : Node = ex.get_node_or_null("SimBrain") if ex != null else null
	if brain != null:
		var m : ExtruderModel = brain.get("model")
		m.set_screw_rpm_setpoint(80.0)
		m.set_zone_temp(2, 205.0)
	_tick_all(bm1, lf1, 25.0, false)          # PLC walks the line up
	if brain != null:
		(brain.get("_pending") as Dictionary)["start_production"] = true
	var nodes : Array = lf1.get("_nodes")
	for nd in nodes:
		if String((nd as Dictionary).get("id", "")) == "compactorband":
			var key : String = String((nd as Dictionary).get("key", ""))
			lf1.call("set_machine_hand_mode", key, true)
			lf1.call("set_machine_manual_on", key, true)
			lf1.call("set_machine_rpm_pct", key, 0.7)
			break
	_tick_all(bm1, lf1, RUN_S, true)
	_summary("BEFORE SAVE", bm1, lf1)

	var times : Array = []
	for _i in 5:
		var t_save : int = Time.get_ticks_usec()
		bm1.call("_save_layout")
		times.append((Time.get_ticks_usec() - t_save) / 1000.0)
	times.sort()
	print("[SAVED] _save_layout median %.1f ms of 5 (min %.1f, max %.1f); file %d bytes"
		% [times[2], times[0], times[4], FileAccess.get_file_as_bytes(FACTORY_PATH).size()])
	var saved : Variant = AtomicFile.read_json(FACTORY_PATH, TYPE_ARRAY)
	var keys : Dictionary = {}
	if saved is Array:
		for e in saved:
			if e is Dictionary:
				for k in (e as Dictionary).keys():
					keys[k] = int(keys.get(k, 0)) + 1
	print("[SAVED] %d entries; keys written: %s" % [(saved as Array).size() if saved is Array else -1, str(keys)])

	bm1.queue_free()
	lf1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var bm2 := BuildMode.new()
	bm2.layout_path = FACTORY_PATH
	bm2.load_shared_structure = false
	bm2.allow_legacy_fallback = false
	add_child(bm2)
	await get_tree().process_frame
	var lf2 := LineFlow.new()
	add_child(lf2)
	await get_tree().process_frame
	lf2.call("rebuild")
	_summary("AFTER LOAD", bm2, lf2)
	# What MainWorld does next since 2026-09-25 (MainWorld._resume_plant). The
	# lines above are what every load gave before: nothing of the run came back.
	bm2.line_flow = lf2
	var rep : Dictionary = preload("res://src/sim/PlantResume.gd").resume_build_mode(bm2, lf2, self)
	print("[RESUME] %s" % str(rep))
	_summary("AFTER RESUME", bm2, lf2)
	_tick_all(bm2, lf2, 5.0, false)
	_summary("AFTER RESUME +5 s", bm2, lf2)

	if OS.get_environment("RESUME_PROBE_KEEP") == "":
		AtomicFile.delete(FACTORY_PATH)
	AtomicFile.delete(WORLD_PATH)
	_done = true
	print("Result: PROBE DONE")
	get_tree().quit(0)
