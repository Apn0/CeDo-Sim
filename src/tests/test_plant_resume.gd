extends Node
## RESUME ON LOAD — a saved plant comes back as it was: run state, settings,
## material and latched faults, compared by name before the save and after the
## load, and then shown to keep behaving that way.
##
##   godot --headless --path . res://src/tests/test_plant_resume.tscn
##
## WHY THIS FILE EXISTS. Operator 2026-09-25 (docs/plant/operator_rulings_2026-09-25.md
## §R1-§R3, CLAIMED): "during normal gameplay or during normal shifts, I would like
## the state to be as it was at the end of the shift before." Measured before the
## change (src/tests/probe_resume_baseline.gd): line 3B running (25 of 25 powered,
## extruder RUNNING at 80 rpm, zone 3 at 205 °C, a belt in HAND at 70 %, 7 kg in
## the pipes) reloaded as 0 powered, extruder OFF and cooling, setpoint 60, zones
## 215, no HAND, 0 kg. Now each placed body's run state rides in its factory entry
## and src/sim/PlantResume.gd puts it back after the load's LineFlow rebuild.
##
##   A  RUNNING LINES. Lines 1 and 3B built, the line started, 3B's extruder
##      started through its own button with the operator's settings changed (rpm
##      80, zone 3 205 °C), a belt in HAND at 70 %, a motor component at 60 %,
##      line 1's extruder left OFF with its hidden natraject setting OFF, a hot lump
##      cart, 60 s fed: 3B's extruder silo with clean dry flake, line 1's head with
##      a wet, dirty bale sample (WET_ORIGIN). Saved, loaded into a fresh BuildMode
##      + LineFlow, resumed.
##      Every body's run state and the line's own must be identical by name; a save
##      BEFORE the resume must write the stash back unchanged; and the resumed line
##      must keep running (never unpowered, extruder at 80 rpm) and keep making
##      granulate, with the kg ledger's residual unchanged. A11: every body's
##      water and contaminant kg come back, walked in LineFlow itself rather than
##      through the capture (2026-09-26: with batch_in dropping contaminant_kg this
##      suite still passed 62 of 62, because nothing it fed carried any dirt).
##   B  LATCHED FAULTS. Line 3A plus a compactor, a NIR sorter, a kopfilter, a
##      bezinktank, a waste bin and a level sensor. A friction separator's motor
##      tripped, a machine choked on a full chute pile, a buffer past the e-stop,
##      the laserfilter caked to its 318-bar trip (extruder EMERGENCY_STOP), a
##      failed start latching the start alarm. After the reload every latch is
##      back, the alarms are raised again for this session, the latches hold on the
##      next ticks, and they reset the way they always did (the choke only once the
##      pile is shovelled). B7: two chute spills under one parent, and two
##      laserfilters' nozzle-0 lump spills under one parent, keep readable names
##      through the save (2026-09-26: the second of each was "@Node3D@N" and came
##      back "_Node3D_N").
##   C  A REAL MAINWORLD BOOT on phase A's save, mid-shift (4 h in): MainWorld's
##      own load path resumes the plant, and a hot lump cart is still hot (its cool
##      timer used to be anchored before the shift clock loaded).
##   Z  the slot files are gone, the leak guard, every phase ran to its last line.
##
## ISOLATION. Everything goes to this suite's slot (__plantresume__*); phases A/B
## use BuildModes with load_shared_structure off; world_layout_guard redirects
## every WorldLayout write for the whole run and proves the real file untouched.

const SLOT := "__plantresume__"
const FACTORY_PATH := "user://__plantresume___factory.json"     # = SystemsSpawner's path for SLOT
const SAVE_PATH    := "user://__plantresume___save.json"
const FACTORY_B    := "user://__plantresume___b_factory.json"
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
const Resume := preload("res://src/sim/PlantResume.gd")
const WATCHDOG_MS : int = 900000
const FEED_KG_H : float = 950.0
## Line 1's head is fed what a bale feeds it (BaleDefs.feed_sample): Alba Marl is
## the wettest and dirtiest origin there (12 % moisture, 14 % dirt).
const WET_ORIGIN : String = "alba_marl"
const SHIFT_ELAPSED_S : float = 4.0 * 3600.0
## A lump cart's cool timer runs on the wall clock in phases A/B (no ShiftClock
## in the tree), so it moves by the real seconds between two captures.
const COOL_TOL_S : float = 120.0
const PHASES : Array = ["A", "B", "C"]

var _ok : int = 0
var _fails : int = 0
var _t0 : int = 0
var _done : bool = false
var _phases_done : Dictionary = {}
var _wlg = null
var _alarms : Array = []
var _world : Node = null
var hand_label : String = ""
var comp_label : String = ""

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_ok += 1
	else:
		_fails += 1

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

## Hang guard (CLAUDE.md, 2026-09-22): a SCRIPT ERROR after an await would
## otherwise leave headless Godot idling with no verdict.
func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		_cleanup_files()
		print("Result: FAIL (watchdog — no verdict after %d s)" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

# ── helpers ──────────────────────────────────────────────────────────────────

func _new_build_mode(path: String) -> BuildMode:
	var bm := BuildMode.new()
	bm.layout_path = path                  # BEFORE add_child: _ready → load_layout()
	bm.load_shared_structure = false
	bm.allow_legacy_fallback = false
	add_child(bm)
	return bm

func _placed(bm: Node) -> Array:
	var root : Node = bm.get("_placed_root")
	return root.get_children() if root != null else []

## macro_instance → ordinal per macro_id, in scene order (a load keeps order).
func _label(n: Node, ords: Dictionary) -> String:
	var id : String = String(n.get_meta("placeable_id", n.name))
	if n.has_meta("macro_id"):
		var key : String = "%s|%s" % [String(n.get_meta("macro_id")), String(n.get_meta("macro_instance", ""))]
		return "%s#%d[%d]%s" % [String(n.get_meta("macro_id")), int(ords.get(key, -1)),
			int(n.get_meta("macro_index", -1)), id]
	var p : Vector3 = (n as Node3D).global_position if n is Node3D else Vector3.ZERO
	return "%s@(%.0f,%.0f)" % [id, p.x, p.z]

func _ordinals(bm: Node) -> Dictionary:
	var out : Dictionary = {}
	var per : Dictionary = {}
	for c in _placed(bm):
		if not c.has_meta("macro_id"):
			continue
		var key : String = "%s|%s" % [String(c.get_meta("macro_id")), String(c.get_meta("macro_instance", ""))]
		if out.has(key):
			continue
		var mid : String = String(c.get_meta("macro_id"))
		out[key] = int(per.get(mid, 0))
		per[mid] = int(per.get(mid, 0)) + 1
	return out

## Every body's run state by name, as the save writes it.
func _capture(bm: Node, lf: Node) -> Dictionary:
	var ords := _ordinals(bm)
	var out : Dictionary = {}
	for c in _placed(bm):
		var st : Dictionary = Resume.capture_body(c as Node3D, lf)
		if not st.is_empty():
			out[_label(c, ords)] = st
	return out

func _find(bm: Node, id: String, macro_id: String = "") -> Node3D:
	for c in _placed(bm):
		if String(c.get_meta("placeable_id", "")) == id \
				and (macro_id == "" or String(c.get_meta("macro_id", "")) == macro_id):
			return c as Node3D
	return null

func _brain(body: Node) -> Node:
	return body.get_node_or_null("SimBrain") if body != null else null

func _brains_under(root: Node) -> Array:
	var out : Array = []
	for b in get_tree().get_nodes_in_group("extruder_machine"):
		if root.is_ancestor_of(b):
			out.append(b)
	return out

func _powered_count(lf: Node) -> int:
	var n := 0
	for nd in lf.get("_nodes"):
		if bool((nd as Dictionary).get("powered", false)):
			n += 1
	return n

## kg held in the line: buffers' in/out batches plus the pipes.
func _inline_kg(lf: Node) -> float:
	var kg := 0.0
	for nd in lf.get("_nodes"):
		for k in ["in", "out"]:
			var b = (nd as Dictionary).get(k, null)
			if b != null:
				kg += (b as MaterialBatch).mass_kg
	return kg + float(lf.call("pipe_mass"))

## label → [mass, water, contaminant] kg of every batch a body's LineFlow node
## holds: its in/out batches, a compactor's pot charge, and the pipes leaving
## it. Read from LineFlow itself, not through PlantResume's capture, so a
## sub-mass the capture and the restore both forgot is still seen.
func _submass(bm: Node, lf: Node) -> Dictionary:
	var ords := _ordinals(bm)
	var nodes : Array = lf.get("_nodes")
	var out : Dictionary = {}
	var batches : Dictionary = {}          # node index → [MaterialBatch]
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var bs : Array = [nd.get("in", null), nd.get("out", null)]
		if nd.get("cc", null) != null:
			bs.append(nd["cc"].get("charge"))
		batches[i] = bs
	for e in lf.get("_edges"):
		(batches[int((e as Dictionary)["a"])] as Array).append_array((e as Dictionary).get("pipe", []))
	for i in nodes.size():
		var body : Node = (nodes[i] as Dictionary).get("node", null)
		if body == null or not is_instance_valid(body):
			continue
		var s : Array = [0.0, 0.0, 0.0]
		for b in (batches[i] as Array):
			if b is MaterialBatch:
				s[0] += (b as MaterialBatch).mass_kg
				s[1] += (b as MaterialBatch).water_kg
				s[2] += (b as MaterialBatch).contaminant_kg
		out[_label(body, ords)] = s
	return out

func _submass_sum(sub: Dictionary) -> Dictionary:
	var out : Dictionary = {"mass": 0.0, "water": 0.0, "contam": 0.0, "n_water": 0, "n_contam": 0}
	for lab in sub:
		var s : Array = sub[lab]
		out["mass"] = float(out["mass"]) + float(s[0])
		out["water"] = float(out["water"]) + float(s[1])
		out["contam"] = float(out["contam"]) + float(s[2])
		if float(s[1]) > 1e-6:
			out["n_water"] = int(out["n_water"]) + 1
		if float(s[2]) > 1e-6:
			out["n_contam"] = int(out["n_contam"]) + 1
	return out

func _tick(bm: Node, lf: Node, secs: float, feed: Array = [], wet_feed: Array = []) -> Dictionary:
	var brains := _brains_under(bm)
	var nodes : Array = lf.get("_nodes")
	var kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var min_powered : int = 1 << 30
	var min_rpm : Dictionary = {}
	for t in int(round(secs / 0.1)):
		for fi in feed:
			(((nodes[int(fi)] as Dictionary)["in"]) as MaterialBatch).add(MaterialBatch.new(
				kg_tick, kg_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "resume_suite", 0.0, 0.0))
		for wi in wet_feed:
			(((nodes[int(wi)] as Dictionary)["in"]) as MaterialBatch).add(BaleDefs.feed_sample(WET_ORIGIN, kg_tick))
		lf.call("tick", 0.1)
		for b in brains:
			b.call("_on_sim_tick", 0.1)
			var m = b.get("model")
			var lid : String = String(b.get("config_resource").line_id)
			min_rpm[lid] = minf(float(min_rpm.get(lid, INF)), float(m.screw_rpm))
		min_powered = mini(min_powered, _powered_count(lf))
	return {"min_powered": min_powered, "min_rpm": min_rpm}

func _node_index(lf: Node, body: Node) -> int:
	var nodes : Array = lf.get("_nodes")
	for i in nodes.size():
		if (nodes[i] as Dictionary).get("node", null) == body:
			return i
	return -1

## Structural difference of two JSON-ish values, as "path: a != b" lines.
func _jdiff(a: Variant, b: Variant, path: String, out: Array) -> void:
	if out.size() >= 12:
		return
	var ta := typeof(a)
	var tb := typeof(b)
	var na : bool = ta == TYPE_INT or ta == TYPE_FLOAT
	var nb : bool = tb == TYPE_INT or tb == TYPE_FLOAT
	if na and nb:
		var tol : float = COOL_TOL_S if path.ends_with("cool_left_s") else maxf(1e-4, absf(float(a)) * 1e-6)
		if absf(float(a) - float(b)) > tol:
			out.append("%s: %s != %s" % [path, str(a), str(b)])
		return
	if ta != tb:
		out.append("%s: %s != %s" % [path, str(a).left(60), str(b).left(60)])
		return
	if ta == TYPE_DICTIONARY:
		for k in (a as Dictionary):
			if not (b as Dictionary).has(k):
				out.append("%s.%s: only before" % [path, str(k)])
			else:
				_jdiff((a as Dictionary)[k], (b as Dictionary)[k], "%s.%s" % [path, str(k)], out)
		for k2 in (b as Dictionary):
			if not (a as Dictionary).has(k2):
				out.append("%s.%s: only after" % [path, str(k2)])
	elif ta == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			out.append("%s: %d items != %d" % [path, (a as Array).size(), (b as Array).size()])
			return
		for i in (a as Array).size():
			_jdiff((a as Array)[i], (b as Array)[i], "%s[%d]" % [path, i], out)
	elif a != b:
		out.append("%s: %s != %s" % [path, str(a).left(60), str(b).left(60)])

## The file's run entries in file order, and its plant_run.
func _file_runs(path: String) -> Dictionary:
	var arr : Variant = AtomicFile.read_json(path, TYPE_ARRAY)
	var runs : Array = []
	var plant : Variant = null
	if arr is Array:
		for e in (arr as Array):
			if not (e is Dictionary):
				continue
			if (e as Dictionary).has("plant_run"):
				plant = (e as Dictionary)["plant_run"]
			elif (e as Dictionary).has("run"):
				runs.append([String((e as Dictionary).get("id", "")), (e as Dictionary)["run"]])
	return {"runs": runs, "plant": plant}

func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

## The loose piles are world nodes (LineFlow parents them to the current scene
## or itself): gone with the world, as they are when a save is closed. Left in
## the tree, the next capture counts them twice, and a restored pile named like
## one still standing is renamed by add_child ("ChuteSpill" → "@Node3D@N").
func _free_loose_piles() -> void:
	for p in get_tree().get_nodes_in_group("floor_pile"):
		if not p.has_meta("placeable_id"):
			p.queue_free()

func _cleanup_files() -> void:
	for p in [FACTORY_PATH, SAVE_PATH, FACTORY_B]:
		AtomicFile.delete(p)

func _on_alarm(machine: String, alarm: String, _sev: int) -> void:
	_alarms.append("%s|%s" % [machine, alarm])

# ── the run ──────────────────────────────────────────────────────────────────

func _run() -> void:
	print("[TEST] plant resume — a saved plant comes back as it was, by name, and keeps running")
	var bus := get_node_or_null("/root/EventBus")
	if bus == null:
		print("Result: FAIL (EventBus autoload missing — boot the .tscn, not --script)")
		_done = true
		get_tree().quit(2)
		return
	_cleanup_files()
	_wlg = WorldLayoutGuard.new(SLOT, [])
	if not _wlg.arm(get_tree()):
		print("Result: FAIL (world_layout guard did not arm — refusing to boot a world)")
		_done = true
		get_tree().quit(2)
		return
	bus.machine_alarm_raised.connect(_on_alarm)
	var floor_body := StaticBody3D.new()
	floor_body.name = "TestFloor"
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4000.0, 1.0, 2000.0)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(400.0, -0.5, 0.0)
	add_child(floor_body)
	await _phase_a()
	await _phase_b()
	floor_body.queue_free()
	await _phase_c()
	_finish()

# ── A: running lines ─────────────────────────────────────────────────────────

func _phase_a() -> void:
	print("  -- A: lines 1 and 3B running — save, load, resume --")
	var bm1 := _new_build_mode(FACTORY_PATH)
	await get_tree().process_frame
	bm1.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	bm1.call("_build_full_line", "line_3b", Vector3(400.0, 0.0, 0.0), 0.0)
	await get_tree().process_frame
	var lf1 := LineFlow.new()
	add_child(lf1)
	lf1.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	bm1.line_flow = lf1
	await get_tree().process_frame
	lf1.call("rebuild")
	var ex3b := _find(bm1, "extruder_3b")
	var ex1 := _find(bm1, "extruder_1")
	var b3b := _brain(ex3b)
	var b1 := _brain(ex1)
	_check(b3b != null and b1 != null, "A0 both extruders have a brain")
	if b3b == null or b1 == null:
		_free(bm1); _free(lf1)
		return
	var m3b = b3b.get("model")
	var m1 = b1.get("model")
	lf1.call("start_line")
	m3b.set_screw_rpm_setpoint(80.0)
	m3b.set_zone_temp(2, 205.0)
	m1.start_seq.natraject_enabled = false          # the hidden setting, OFF on line 1
	_tick(bm1, lf1, 25.0)                           # the PLC walks the line up
	(b3b.get("_pending") as Dictionary)["start_production"] = true
	var nodes : Array = lf1.get("_nodes")
	var hand_key := ""
	var comp_key := ""
	var comp_name := ""
	var hand_body : Node = null
	var comp_body : Node = null
	var silo_i := -1
	var wet_heads : Array = []
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var body : Node = nd.get("node", null)
		if body != null and String(body.get_meta("macro_id", "")) == "line_1" \
				and String(nd.get("role", "")) != "sink" and not bool(lf1.call("_has_incoming", i)):
			wet_heads.append(i)
		if body == null or String(body.get_meta("macro_id", "")) != "line_3b":
			continue
		if String(nd.get("id", "")) == "compactorband" and hand_key == "":
			hand_key = String(nd.get("key", ""))
			hand_body = body
		if String(nd.get("id", "")) == "extruder_silo":
			silo_i = i
		if comp_key == "" and (nd.get("components", {}) as Dictionary).size() >= 2:
			comp_key = String(nd.get("key", ""))
			comp_name = String((nd.get("components", {}) as Dictionary).keys()[1])
			comp_body = body
	lf1.call("set_machine_hand_mode", hand_key, true)
	lf1.call("set_machine_manual_on", hand_key, true)
	lf1.call("set_machine_rpm_pct", hand_key, 0.7)
	if comp_key != "":
		lf1.call("set_machine_component_pct", comp_key, comp_name, 0.6)
	_tick(bm1, lf1, 60.0, [silo_i] if silo_i >= 0 else [], wet_heads)
	var cart := _find(bm1, "lump_cart", "line_3b")
	if cart != null:
		cart.call("receive_lump", 30.0)
	# Anti-vacuity: the world really is running and holds what this suite compares.
	var n_nodes : int = (lf1.get("_nodes") as Array).size()
	var pow1 : int = _powered_count(lf1)
	var kg1 : float = _inline_kg(lf1)
	var pipes1 : float = float(lf1.call("pipe_mass"))
	var gran1 : float = float(lf1.get("gran_mass"))
	var resid1 : float = float(lf1.call("ledger_residual"))
	print("  info  : before save — %d nodes, %d powered, %.1f kg in line (%.1f kg in pipes), granulaat %.1f kg, 3B %s at %.1f rpm"
		% [n_nodes, pow1, kg1, pipes1, gran1, m3b.get_state_name(), m3b.screw_rpm])
	_check(m3b.state == ExtruderModel.State.RUNNING and absf(m3b.screw_rpm - 80.0) < 0.5,
		"A1 before the save 3B's extruder runs at its setpoint (%s, %.1f rpm)" % [m3b.get_state_name(), m3b.screw_rpm])
	_check(pow1 > n_nodes / 2 and kg1 > 1.0 and pipes1 > 0.1 and gran1 > 0.1,
		"A1 before the save the line is powered and holds material (%d/%d powered, %.1f kg, %.2f kg in pipes, %.1f kg granulaat)"
		% [pow1, n_nodes, kg1, pipes1, gran1])
	_check(hand_key != "" and comp_key != "" and cart != null and float(cart.get("lumps_kg")) > 29.0,
		"A1 fixtures: a belt in HAND (%s), a component at 60 %% (%s.%s), a hot lump cart (%.0f kg)"
		% [hand_key, comp_key, comp_name, float(cart.get("lumps_kg")) if cart != null else -1.0])
	var ords0 : Dictionary = _ordinals(bm1)
	hand_label = _label(hand_body, ords0) if hand_body != null else ""
	comp_label = _label(comp_body, ords0) if comp_body != null else ""
	var t_cap : int = Time.get_ticks_usec()
	var cap1 : Dictionary = _capture(bm1, lf1)
	t_cap = Time.get_ticks_usec() - t_cap
	var line1 : Dictionary = Resume.capture_line(lf1, get_tree())
	var sub1 : Dictionary = _submass(bm1, lf1)
	var sum1 : Dictionary = _submass_sum(sub1)
	var heads : Array = []
	for wi in wet_heads:
		heads.append(_label((nodes[int(wi)] as Dictionary)["node"], ords0))
	print("  info  : sub-masses before save — %.3f kg water in %d bodies, %.3f kg contaminant in %d bodies, of %.3f kg; wash water taken on %.3f kg; wet feed at %s"
		% [float(sum1["water"]), int(sum1["n_water"]), float(sum1["contam"]), int(sum1["n_contam"]),
		float(sum1["mass"]), float(lf1.get("water_added")), str(heads)])
	# Anti-vacuity: the line really carries wet, dirty material through several
	# machines and their pipes, not only at the head it was poured into.
	# Measured 2026-09-26: 3.25 kg water in 40 bodies, 0.54 kg contaminant in 37,
	# 11.06 kg wash water taken on; the floors sit at about half of that.
	_check(heads.size() >= 1 and float(sum1["water"]) > 1.5 and float(sum1["contam"]) > 0.25 \
			and int(sum1["n_contam"]) >= 15 and float(lf1.get("water_added")) > 5.0,
		"A1 fixture: line 1 carries wet, dirty feed (%.2f kg water in %d bodies, %.2f kg contaminant in %d bodies, wash water %.2f kg)"
		% [float(sum1["water"]), int(sum1["n_water"]), float(sum1["contam"]), int(sum1["n_contam"]), float(lf1.get("water_added"))])
	var t_save : int = Time.get_ticks_usec()
	bm1.call("_save_layout")
	t_save = Time.get_ticks_usec() - t_save
	# Measured, not gated: what the run state adds to every autosave and
	# placement (the capture is the new part of _save_layout).
	print("  info  : cost — capturing %d bodies' run state %.1f ms; the whole _save_layout %.1f ms (%d placed bodies, file %d bytes)"
		% [cap1.size(), t_cap / 1000.0, t_save / 1000.0, _placed(bm1).size(),
		FileAccess.get_file_as_bytes(FACTORY_PATH).size()])
	var file1 : Dictionary = _file_runs(FACTORY_PATH)
	_check((file1["runs"] as Array).size() == cap1.size() and cap1.size() >= 40,
		"A2 the save wrote a run state for every body that has one (%d entries, %d captured)"
		% [(file1["runs"] as Array).size(), cap1.size()])
	_check(file1["plant"] is Dictionary and ((file1["plant"] as Dictionary).get("lf", {}) as Dictionary).has("gran_mass"),
		"A2 the save wrote the line's own state (plant_run with the kg ledger)")
	var want_types : Array = ["extruder_3b", "extruder_1", "laser_filter", "lump_cart", "shredder_1", "opzetband_1", "compactorband"]
	var have_types : Dictionary = {}
	for lab in cap1:
		for t in want_types:
			if String(lab).ends_with("]" + String(t)):
				have_types[t] = true
	_check(have_types.size() == want_types.size(),
		"A2 the run states cover the extruder brains, laserfilter, lump cart, shredder, opzetband, belts (%s)" % str(have_types.keys()))

	_free(bm1)
	_free(lf1)
	_free_loose_piles()           # line 1's dirt spills on the floor (the wet feed)
	await get_tree().process_frame
	await get_tree().process_frame
	var bm2 := _new_build_mode(FACTORY_PATH)
	await get_tree().process_frame
	var lf2 := LineFlow.new()
	add_child(lf2)
	lf2.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	bm2.line_flow = lf2
	await get_tree().process_frame
	lf2.call("rebuild")
	var ex3b2 := _find(bm2, "extruder_3b")
	var b3b2 := _brain(ex3b2)
	var m3b2 = b3b2.get("model") if b3b2 != null else null
	# Before the resume the load is the old cold world: the resume is what does it.
	_check(m3b2 != null and m3b2.state == ExtruderModel.State.OFF and _powered_count(lf2) == 0,
		"A3 loaded, not yet resumed: extruder %s, %d powered (the cold world the load always gave)"
		% [m3b2.get_state_name() if m3b2 != null else "?", _powered_count(lf2)])
	# A save that runs before the resume writes the stash back, not the cold state.
	bm2.call("_save_layout")
	var file2 : Dictionary = _file_runs(FACTORY_PATH)
	var d_file : Array = []
	_jdiff(file1, file2, "file", d_file)
	_check(d_file.is_empty(), "A4 a save before the resume writes back what was saved %s" % (str(d_file) if not d_file.is_empty() else "(identical)"))
	var rep : Dictionary = Resume.resume_build_mode(bm2, lf2, self)
	print("  info  : resume report %s" % str(rep))
	_check(int(rep.get("bodies", 0)) == cap1.size() and (rep.get("missed", []) as Array).is_empty(),
		"A5 the resume applied every saved body (%d of %d) and missed nothing %s"
		% [int(rep.get("bodies", 0)), cap1.size(), str(rep.get("missed", []))])
	var cap2 : Dictionary = _capture(bm2, lf2)
	var line2 : Dictionary = Resume.capture_line(lf2, get_tree())
	var sub2 : Dictionary = _submass(bm2, lf2)      # checked in A11, before A8 ticks it
	var bad : Array = []
	for lab in cap1:
		var d : Array = []
		_jdiff(cap1[lab], cap2.get(lab, null), String(lab), d)
		if not d.is_empty():
			bad.append(d[0] if d.size() == 1 else "%s (+%d more)" % [d[0], d.size() - 1])
	_check(cap1.size() == cap2.size() and bad.is_empty(),
		"A6 every body's run state is identical by name after the resume (%d before, %d after) %s"
		% [cap1.size(), cap2.size(), str(bad.slice(0, 8)) if not bad.is_empty() else ""])
	var d_line : Array = []
	_jdiff(line1, line2, "line", d_line)
	_check(d_line.is_empty(), "A6 the line's own state (ledger, PLC, piles) is identical %s" % (str(d_line) if not d_line.is_empty() else ""))
	# Named, for the reader: what the operator asked for, one by one.
	var m1b = _brain(_find(bm2, "extruder_1")).get("model")
	_check(m3b2.state == ExtruderModel.State.RUNNING and absf(m3b2.screw_rpm - 80.0) < 0.5 \
			and absf(m3b2.screw_rpm_setpoint - 80.0) < 0.01 and absf(m3b2.zone_temp_setpoints[2] - 205.0) < 0.01,
		"A7 3B's extruder: %s at %.1f rpm, setpoint %.0f, zone 3 %.0f °C" % [m3b2.get_state_name(),
			m3b2.screw_rpm, m3b2.screw_rpm_setpoint, m3b2.zone_temp_setpoints[2]])
	_check(m3b2.start_seq.phase == 2 and (m3b2.start_seq.run_cmd as Dictionary).values().all(func(v): return bool(v)),
		"A7 3B's start sequence: phase SCREW, natraject commanded on %s" % str(m3b2.start_seq.run_cmd))
	_check(m1b.state == ExtruderModel.State.OFF and not m1b.start_seq.natraject_enabled,
		"A7 line 1's extruder stays OFF with its natraject setting OFF (%s, natraject %s)" % [m1b.get_state_name(), str(m1b.start_seq.natraject_enabled)])
	var hand2 : Node = null
	var comp2 : Node = null
	var ords2 : Dictionary = _ordinals(bm2)
	for c in _placed(bm2):
		var lab2 : String = _label(c, ords2)
		if lab2 == hand_label:
			hand2 = c
		if lab2 == comp_label:
			comp2 = c
	var hnd : Dictionary = lf2.call("node_for_body", hand2) if hand2 != null else {}
	_check(bool(hnd.get("hand_mode", false)) and bool(hnd.get("manual_on", false)) and absf(float(hnd.get("rpm_pct", 0.0)) - 0.7) < 1e-6,
		"A7 %s in HAND, manual on, 70 %% (hand %s, manual %s, rpm %.3f)" % [hand_label,
			str(hnd.get("hand_mode", "?")), str(hnd.get("manual_on", "?")), float(hnd.get("rpm_pct", -1.0))])
	var cnd : Dictionary = lf2.call("node_for_body", comp2) if comp2 != null else {}
	_check(absf(float((cnd.get("components", {}) as Dictionary).get(comp_name, 0.0)) - 0.6) < 1e-6,
		"A7 %s component %s at 60 %%" % [comp_key, comp_name])
	var pow2 : int = _powered_count(lf2)
	var kg2 : float = _inline_kg(lf2)
	_check(pow2 == pow1 and absf(kg2 - kg1) < 1e-3,
		"A7 %d of %d powered (was %d), %.4f kg in the line (was %.4f)" % [pow2, n_nodes, pow1, kg2, kg1])
	var cart2 := _find(bm2, "lump_cart", "line_3b")
	# The hot cart: the lump cart's line entry keeps its lumps_kg too.
	var cart_hot : float = float(cart2.call("cool_remaining_s")) if cart2 != null else 0.0
	_check(cart2 != null and absf(float(cart2.get("lumps_kg")) - 30.0) < 1e-3 and cart_hot > 3000.0,
		"A7 the lump cart holds 30 kg and is still hot (%.0f s to cool)" % cart_hot)
	# Behaviour: the resumed line keeps running. Before the fix every node was
	# unpowered after the load; a resume that skips the PLC's pre-power would
	# drop them all on the first tick.
	var gran2 : float = float(lf2.get("gran_mass"))
	var resid2 : float = float(lf2.call("ledger_residual"))
	var silo2 := -1
	var nodes2 : Array = lf2.get("_nodes")
	for i in nodes2.size():
		var b = (nodes2[i] as Dictionary).get("node", null)
		if b != null and String(b.get_meta("macro_id", "")) == "line_3b" \
				and String((nodes2[i] as Dictionary).get("id", "")) == "extruder_silo":
			silo2 = i
	var run : Dictionary = _tick(bm2, lf2, 10.0, [silo2] if silo2 >= 0 else [])
	var gran3 : float = float(lf2.get("gran_mass"))
	_check(int(run["min_powered"]) == pow1,
		"A8 over 10 s after the resume no machine dropped out (fewest powered %d, saved %d)" % [int(run["min_powered"]), pow1])
	_check(float((run["min_rpm"] as Dictionary).get("3B", 0.0)) > 79.5 and m3b2.state == ExtruderModel.State.RUNNING,
		"A8 3B's screw never left its 80 rpm (lowest %.1f rpm, now %s) — no re-start, no ramp" % [float((run["min_rpm"] as Dictionary).get("3B", 0.0)), m3b2.get_state_name()])
	_check(gran3 > gran2 + 0.01, "A8 the resumed line makes granulate (%.2f kg → %.2f kg in 10 s)" % [gran2, gran3])
	_check(absf(resid2 - resid1) < 1e-3,
		"A9 the kg ledger balances across the reload (residual %.5f before the save, %.5f after the resume)" % [resid1, resid2])
	# A rebuild mid-session (an HMI placed) keeps the settings too. The
	# per-component rpm was missing from rebuild()'s survivor list until
	# 2026-09-25: every rebuild put it back to 100 %.
	lf2.call("rebuild")
	var cnd2 : Dictionary = lf2.call("node_for_body", comp2) if comp2 != null else {}
	var hnd2 : Dictionary = lf2.call("node_for_body", hand2) if hand2 != null else {}
	_check(absf(float((cnd2.get("components", {}) as Dictionary).get(comp_name, 0.0)) - 0.6) < 1e-6 \
			and bool(hnd2.get("hand_mode", false)) and absf(float(hnd2.get("rpm_pct", 0.0)) - 0.7) < 1e-6,
		"A10 a rebuild keeps the settings: %s at %.2f, %s HAND at %.2f"
		% [comp_name, float((cnd2.get("components", {}) as Dictionary).get(comp_name, -1.0)),
			hand_label, float(hnd2.get("rpm_pct", -1.0))])
	# The sub-masses by name: a reloaded wet line must not come back dry, nor a
	# dirty one clean. material_census.py cannot see this carry (PlantResume
	# restores the sub-masses by dict key, which it reads as a string), so this
	# is the check that does; the census lists PlantResume as a load boundary.
	var sub_bad : Array = []
	for lab3 in sub1:
		var s1 : Array = sub1[lab3]
		var s2 : Array = sub2.get(lab3, [])
		if s2.size() != 3:
			sub_bad.append("%s: missing after the resume" % lab3)
			continue
		for q in 3:
			if absf(float(s1[q]) - float(s2[q])) > maxf(1e-6, absf(float(s1[q])) * 1e-6):
				sub_bad.append("%s.%s: %.6f != %.6f" % [lab3, ["mass_kg", "water_kg", "contaminant_kg"][q], float(s1[q]), float(s2[q])])
	var sum2 : Dictionary = _submass_sum(sub2)
	_check(sub1.size() == sub2.size() and sub_bad.is_empty(),
		"A11 every body's water and contaminant come back by name: %.4f kg water (was %.4f), %.4f kg contaminant (was %.4f) %s"
		% [float(sum2["water"]), float(sum1["water"]), float(sum2["contam"]), float(sum1["contam"]),
		str(sub_bad.slice(0, 6)) if not sub_bad.is_empty() else ""])
	_free(bm2)
	_free(lf2)
	_free_loose_piles()
	await get_tree().process_frame
	await get_tree().process_frame
	_phases_done["A"] = true

# ── B: latched faults ────────────────────────────────────────────────────────

func _place(bm: Node, id: String, at: Vector3) -> Node3D:
	var before : int = _placed(bm).size()
	bm.call("_apply_layout_entry", {"id": id, "x": at.x, "y": at.y, "z": at.z, "rot_y": 0.0, "h": 0.0})
	var all : Array = _placed(bm)
	return all[all.size() - 1] as Node3D if all.size() > before else null

func _phase_b() -> void:
	print("  -- B: latched faults — save, load, resume --")
	var bm1 := _new_build_mode(FACTORY_B)
	await get_tree().process_frame
	bm1.call("_build_full_line", "line_3a", Vector3.ZERO, 0.0)
	# Line 3C for its DRD pair (L3C.14 L/R): the only line whose dryers run a
	# MechDryerCycle, which the resume must bring back mid-cycle.
	bm1.call("_build_full_line", "line_3c", Vector3(-800.0, 0.0, 0.0), 0.0)
	var cc_body := _place(bm1, "compactor", Vector3(300.0, 0.0, 300.0))
	var nir_body := _place(bm1, "titech_sort", Vector3(400.0, 0.0, 300.0))
	var kop_body := _place(bm1, "kopfilter", Vector3(500.0, 0.0, 300.0))
	var bez_body := _place(bm1, "sink_float", Vector3(600.0, 0.0, 300.0))
	var bin_body := _place(bm1, "waste_container", Vector3(700.0, 0.0, 300.0))
	var sen_body := _place(bm1, "silo_level_sensor", Vector3(800.0, 0.0, 300.0))
	await get_tree().process_frame
	var lf1 := LineFlow.new()
	add_child(lf1)
	lf1.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	bm1.line_flow = lf1
	lf1.smoke_chance = 0.0
	await get_tree().process_frame
	lf1.call("rebuild")
	var ex := _find(bm1, "extruder_3a")
	var br := _brain(ex)
	_check(br != null and cc_body != null and nir_body != null and kop_body != null and bez_body != null \
			and bin_body != null and sen_body != null, "B0 line 3A and the six extra machines are placed")
	if br == null:
		_free(bm1); _free(lf1)
		return
	var m = br.get("model")
	lf1.call("start_line")
	_tick(bm1, lf1, 25.0)
	(br.get("_pending") as Dictionary)["start_production"] = true
	_tick(bm1, lf1, 20.0)
	_check(m.state == ExtruderModel.State.RUNNING, "B0 3A's extruder runs before the faults (%s)" % m.get_state_name())
	# Machine-owned state, set through each machine's own API.
	bin_body.call("add", 120.0, 400.0, -1)
	sen_body.call("crosshair_interact", null)                # bridged
	var nodes : Array = lf1.get("_nodes")
	var cc_nd : Dictionary = nodes[_node_index(lf1, cc_body)] if _node_index(lf1, cc_body) >= 0 else {}
	if cc_nd.get("cc", null) != null:
		cc_nd["cc"].disc_rpm_setpoint = 1200.0
		cc_nd["cc"].knife_sharpness = 0.7
	var nir_nd : Dictionary = nodes[_node_index(lf1, nir_body)] if _node_index(lf1, nir_body) >= 0 else {}
	if nir_nd.get("nir_ctrl", null) != null:
		nir_nd["nir_ctrl"].shaft_wrap.wrap_g = 210.0
	var kop_cav : Array = kop_body.get("cavities")
	(kop_cav[0]).loading_g = 900.0
	var bez = bez_body.find_child("BezinkTank", true, false)
	if bez != null:
		bez.set("valve_auto", false)
		bez.set("sp_high", 0.7)
	# 0) The extruder silo overfills: its level sensor holds the silo's feed
	#    (rulings §I11, LineFlow._tick_silo_feed_stops) at its next 1 s report.
	var silo_b := _find(bm1, "extruder_silo", "line_3a")
	var silo_i : int = _node_index(lf1, silo_b)
	if silo_i >= 0:
		((nodes[silo_i] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(230.0, 230.0 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "fixture"))
	_tick(bm1, lf1, 1.5)
	var sl1 : Dictionary = lf1.call("silo_level_for", silo_b) if silo_b != null else {}
	# 1) A friction separator's motor trips.
	var mol_key := ""
	var mol_body : Node = null
	for nd in nodes:
		if String((nd as Dictionary).get("id", "")).find("friction") >= 0 and (nd as Dictionary).get("mol", null) != null:
			(nd as Dictionary)["mol"].force_trip()
			mol_key = String((nd as Dictionary).get("key", ""))
			mol_body = (nd as Dictionary).get("node", null)
			break
	# 2) A machine chokes: nothing catches its reject and the chute pile is full.
	var choke_key := ""
	var choke_nd : Dictionary = {}
	for nd2 in nodes:
		var d2 : Dictionary = nd2
		if String(d2.get("id", "")) == "flotation_tank":
			choke_nd = d2
			choke_key = String(d2.get("key", ""))
			break
	var choke_body : Node = choke_nd.get("node", null)
	if not choke_nd.is_empty():
		var wout : Vector3 = choke_nd["wout"]
		lf1.call("_dump_waste", wout, MaterialBatch.new(1.0e6, 1.0e6 / 400.0, LineFlow.DEFAULT_COMP.duplicate(), "fixture"), [], -1, choke_nd)
	# 2b) A second spill of each kind under the same parent (B7): an uncaught
	#     chute beyond LineFlow's 40 m pile search from the first, and nozzle 0
	#     of 3A's and 3C's laserfilters (both spill under the BuildMode).
	lf1.call("_dump_waste", Vector3(0.0, 2.0, 200.0), MaterialBatch.new(5.0, 5.0 / 400.0, LineFlow.DEFAULT_COMP.duplicate(), "fixture"), [], -1)
	for lf_line in ["line_3a", "line_3c"]:
		var lz := _find(bm1, "laser_filter", lf_line)
		if lz != null:
			lz.call("_spill_to_floor", 0, 5.0)
	# 3) A buffer past the e-stop's overload.
	var est_nd : Dictionary = {}
	for nd3 in nodes:
		if String((nd3 as Dictionary).get("id", "")) == "vss_silo":
			est_nd = nd3
			break
	if not est_nd.is_empty():
		(est_nd["in"] as MaterialBatch).add(MaterialBatch.new(400.0, 400.0 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "fixture"))
	_tick(bm1, lf1, 0.2)
	# 4) The laserfilter cakes to its 318-bar trip: its own physics tick trips it,
	#    the brain takes the signal and stops the extruder.
	var laser := _find(bm1, "laser_filter", "line_3a")
	laser.set("front_loading_g", 5.0e6)
	for _i in 4:
		await get_tree().physics_frame
	_tick(bm1, lf1, 0.3)
	# 5) A start pressed with its checks failing latches the start alarm.
	m.start_seq.press({})
	var est_label : String = ""
	var fault_ni : int = int(lf1.get("_estop_fault_node"))
	if fault_ni >= 0:
		est_label = _label((lf1.get("_nodes")[fault_ni] as Dictionary)["node"], _ordinals(bm1))
	print("  info  : faults — mol %s, choke %s (%s), e-stop %s at %s, extruder %s (%s), laser tripped %s, start alarm '%s'"
		% [mol_key, choke_key, str(choke_nd.get("choked", false)), str(lf1.get("_estop_active")), est_label,
		m.get_state_name(), m.fault_reason, str(laser.get("is_tripped")), m.start_seq.alarm])
	_check(mol_key != "" and bool(lf1.call("_is_mol_tripped", lf1.call("_resolve", mol_key))),
		"B1 before the save a friction separator's motor is tripped (%s)" % mol_key)
	_check(bool(choke_nd.get("choked", false)) and choke_nd.get("choke_pile", null) != null,
		"B1 before the save %s is choked on a full chute pile" % choke_key)
	_check(bool(lf1.get("_estop_active")) and est_label != "", "B1 before the save the e-stop is active (%s)" % est_label)
	_check(m.state == ExtruderModel.State.EMERGENCY_STOP and bool(laser.get("is_tripped")) and bool(br.get("_upstream_trip_latched")),
		"B1 before the save the 318-bar trip holds: extruder %s, laserfilter tripped, brain latched" % m.get_state_name())
	_check(String(m.start_seq.alarm) != "", "B1 before the save the start alarm is latched ('%s')" % m.start_seq.alarm)
	_check(bool(sl1.get("held", false)), "B1 before the save 3A's extruder silo holds its feed (%.0f %%)" % float(sl1.get("pct", -1.0)))
	var sl_save : Dictionary = lf1.call("silo_level_for", silo_b) if silo_b != null else {}
	var ordsb : Dictionary = _ordinals(bm1)
	var mol_label : String = _label(mol_body, ordsb) if mol_body != null else ""
	var choke_label : String = _label(choke_body, ordsb) if choke_body != null else ""
	var cap1 : Dictionary = _capture(bm1, lf1)
	var line1 : Dictionary = Resume.capture_line(lf1, get_tree())
	var piles1 : Array = line1.get("piles", [])
	bm1.call("_save_layout")
	_free(bm1)
	_free(lf1)
	_free_loose_piles()
	await get_tree().process_frame
	await get_tree().process_frame
	var bm2 := _new_build_mode(FACTORY_B)
	await get_tree().process_frame
	var lf2 := LineFlow.new()
	add_child(lf2)
	lf2.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	bm2.line_flow = lf2
	lf2.smoke_chance = 0.0
	await get_tree().process_frame
	lf2.call("rebuild")
	_alarms.clear()
	var rep : Dictionary = Resume.resume_build_mode(bm2, lf2, self)
	print("  info  : resume report %s; alarms raised %s" % [str(rep), str(_alarms)])
	var cap2 : Dictionary = _capture(bm2, lf2)
	var line2 : Dictionary = Resume.capture_line(lf2, get_tree())
	var bad : Array = []
	for lab in cap1:
		var d : Array = []
		_jdiff(cap1[lab], cap2.get(lab, null), String(lab), d)
		if not d.is_empty():
			bad.append(d[0] if d.size() == 1 else "%s (+%d more)" % [d[0], d.size() - 1])
	var drd_n : int = 0
	for lab2 in cap1:
		if ((cap1[lab2] as Dictionary).get("lf", {}) as Dictionary).has("drd"):
			drd_n += 1
	_check(drd_n == 2, "B2 the DRD pair's cycles are in the save (%d bodies carry one)" % drd_n)
	_check(cap1.size() == cap2.size() and cap1.size() >= 30 and bad.is_empty(),
		"B2 every body's run state is identical by name after the resume (%d before, %d after) %s"
		% [cap1.size(), cap2.size(), str(bad.slice(0, 8)) if not bad.is_empty() else ""])
	var d_line : Array = []
	_jdiff(line1, line2, "line", d_line)
	_check(d_line.is_empty() and piles1.size() >= 1,
		"B2 the line's own state and its %d loose floor pile(s) are identical %s" % [piles1.size(), str(d_line) if not d_line.is_empty() else ""])
	var names1 : Array = []
	var names2 : Array = []
	for pd1 in piles1:
		names1.append(String((pd1 as Dictionary).get("name", "")))
	for pd2 in (line2.get("piles", []) as Array):
		names2.append(String((pd2 as Dictionary).get("name", "")))
	names1.sort()
	names2.sort()
	var n_chute : int = 0
	var n_lump : int = 0
	var unreadable : Array = []
	for nm in names1:
		if String(nm).begins_with("ChuteSpill"):
			n_chute += 1
		elif String(nm).begins_with("LumpSpill"):
			n_lump += 1
		else:
			unreadable.append(nm)
	_check(n_chute >= 2 and n_lump >= 2 and unreadable.is_empty() and names2 == names1,
		"B7 two spills of each kind under one parent keep readable names through the save (%d chute, %d lump): %s -> %s"
		% [n_chute, n_lump, str(names1), str(names2)])
	var ex2 := _find(bm2, "extruder_3a")
	var br2 := _brain(ex2)
	var m2 = br2.get("model")
	var laser2 := _find(bm2, "laser_filter", "line_3a")
	_check(m2.state == ExtruderModel.State.EMERGENCY_STOP and m2.fault_reason == "laserfilter_upstream_overpressure_318bar" \
			and bool(laser2.get("is_tripped")) and bool(laser2.get("is_halted")) and bool(br2.get("_upstream_trip_latched")),
		"B3 the 318-bar trip is back: extruder %s (%s), laserfilter tripped + halted, brain latched" % [m2.get_state_name(), m2.fault_reason])
	var silo_b2 := _find(bm2, "extruder_silo", "line_3a")
	var sl2 : Dictionary = lf2.call("silo_level_for", silo_b2) if silo_b2 != null else {}
	_check(bool(sl2.get("held", false)) and absf(float(sl2.get("pct", 0.0)) - float(sl_save.get("pct", -1.0))) < 1e-6,
		"B3 the silo's feed stop still holds before its first report (%.0f %% as saved %.0f %%, held %s)"
		% [float(sl2.get("pct", -1.0)), float(sl_save.get("pct", -1.0)), str(sl2.get("held", "?"))])
	_check(String(m2.start_seq.alarm) == String(m.start_seq.alarm) and String(m2.start_seq.alarm) != "",
		"B3 the start alarm is still latched ('%s')" % m2.start_seq.alarm)
	var est2 : String = ""
	if int(lf2.get("_estop_fault_node")) >= 0:
		est2 = _label((lf2.get("_nodes")[int(lf2.get("_estop_fault_node"))] as Dictionary)["node"], _ordinals(bm2))
	_check(bool(lf2.get("_estop_active")) and est2 == est_label and not bool(lf2.get("feed_enabled")),
		"B3 the e-stop is back on the same machine (%s) with the feed off" % est2)
	var ords2 : Dictionary = _ordinals(bm2)
	var mol2 : Node = null
	var choke2 : Node = null
	for c in _placed(bm2):
		var lab : String = _label(c, ords2)
		if lab == mol_label:
			mol2 = c
		if lab == choke_label:
			choke2 = c
	var mnd : Dictionary = lf2.call("node_for_body", mol2) if mol2 != null else {}
	var cnd : Dictionary = lf2.call("node_for_body", choke2) if choke2 != null else {}
	mol_key = String(mnd.get("key", ""))
	choke_key = String(cnd.get("key", ""))
	_check(bool(lf2.call("_is_mol_tripped", mnd)), "B3 %s's motor is still tripped" % mol_label)
	_check(bool(cnd.get("choked", false)) and cnd.get("choke_pile", null) != null and is_instance_valid(cnd["choke_pile"]),
		"B3 %s is still choked and knows the pile that refused it" % choke_key)
	for want in ["MOTOR-OVERLOAD", "CHUTE-BLOCKED", "OVERLOAD-ESTOP", "overpressure", "fault"]:
		var seen := false
		for a in _alarms:
			if String(a).ends_with("|" + String(want)):
				seen = true
		if want == "fault":
			continue   # the extruder is in EMERGENCY_STOP, not FAULT: no "fault" alarm expected
		_check(seen, "B4 the %s alarm is raised again for this session" % want)
	# Behaviour: the latches hold and reset as they always did.
	_tick(bm2, lf2, 1.0)
	_check(not bool(mnd.get("powered", true)) and not bool(cnd.get("powered", true)),
		"B5 a second after the resume the tripped and the choked machine stay stopped")
	_check(m2.state == ExtruderModel.State.EMERGENCY_STOP and bool(lf2.get("_estop_active")),
		"B5 the extruder stays in EMERGENCY_STOP and the e-stop stays active")
	_check(bool(lf2.call("reset_trip", mol_key)), "B6 RESETTEN clears the restored motor trip (%s)" % mol_key)
	_check(not bool(lf2.call("reset_choke", choke_key)), "B6 a reset with the chute pile still full is refused (shovel first)")
	var pile = cnd.get("choke_pile", null)
	if pile != null and is_instance_valid(pile):
		pile.call("scoop", float(pile.get("mass_kg")) * 0.8)
	_check(bool(lf2.call("reset_choke", choke_key)), "B6 once the pile is shovelled the choke resets")
	_free(bm2)
	_free(lf2)
	_free_loose_piles()
	await get_tree().process_frame
	await get_tree().process_frame
	_phases_done["B"] = true

# ── C: a real MainWorld boot on phase A's save ───────────────────────────────

func _phase_c() -> void:
	print("  -- C: a real MainWorld boot on phase A's save, 4 h into the shift --")
	var file : Dictionary = _file_runs(FACTORY_PATH)
	var saved_cool := -1.0
	for r in (file["runs"] as Array):
		if String(r[0]) == "lump_cart":
			var parts : Dictionary = (r[1] as Dictionary).get("parts", {})
			if (parts.get(".", {}) as Dictionary).has("cool_left_s"):
				saved_cool = float((parts["."] as Dictionary)["cool_left_s"])
	_check(saved_cool > 3000.0, "C0 phase A's save holds a hot lump cart (%.0f s to cool)" % saved_cool)
	var save := {"version": 1, "saved_at": int(Time.get_unix_time_from_system()), "is_new_save": false,
		"shift": {"elapsed_seconds": SHIFT_ELAPSED_S, "is_active": true, "day_index": 1, "team_index": 0}}
	_check(AtomicFile.write_json(SAVE_PATH, save, "\t") == OK, "C0 the slot's save file is written")
	var bus := get_node_or_null("/root/EventBus")
	bus.set_meta("pending_save_name", SLOT)
	bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_world = scn.instantiate()
	get_tree().root.add_child(_world)
	for _i in 30:
		await get_tree().process_frame
	var bm : Node = _world.get_node_or_null("BuildMode")
	var lf : Node = _world.get("line_flow")
	_check(bm != null and lf != null, "C1 MainWorld booted with a BuildMode and a LineFlow")
	if bm == null or lf == null:
		_phases_done["C"] = true
		return
	var ex3b := _find(bm, "extruder_3b")
	var ex1 := _find(bm, "extruder_1")
	var m3b = _brain(ex3b).get("model") if _brain(ex3b) != null else null
	var m1 = _brain(ex1).get("model") if _brain(ex1) != null else null
	_check(m3b != null and m3b.state == ExtruderModel.State.RUNNING and absf(m3b.screw_rpm_setpoint - 80.0) < 0.01 \
			and absf(m3b.zone_temp_setpoints[2] - 205.0) < 0.01,
		"C2 MainWorld resumed 3B's extruder: %s, setpoint %.0f rpm, zone 3 %.0f °C"
		% [m3b.get_state_name() if m3b != null else "?", m3b.screw_rpm_setpoint if m3b != null else -1.0,
			m3b.zone_temp_setpoints[2] if m3b != null else -1.0])
	var nd3b : Dictionary = lf.call("node_for_body", ex3b) if ex3b != null else {}
	_check(bool(nd3b.get("powered", false)), "C2 its LineFlow node is powered")
	_check(m1 != null and m1.state == ExtruderModel.State.OFF and not m1.start_seq.natraject_enabled,
		"C2 line 1's extruder is OFF with its natraject setting OFF")
	var left := 0
	for c in _placed(bm):
		if c.has_meta(Resume.META):
			left += 1
	_check(left == 0, "C3 no machine is left with an unapplied saved state (%d)" % left)
	var sc : Node = _world.find_child("ShiftClock", false, false)
	var elapsed : float = float(sc.get("shift_elapsed_seconds")) if sc != null else -1.0
	var cart := _find(bm, "lump_cart", "line_3b")
	var cool : float = float(cart.call("cool_remaining_s")) if cart != null else -1.0
	_check(elapsed >= SHIFT_ELAPSED_S - 1.0 and absf(cool - saved_cool) < COOL_TOL_S,
		"C4 at %.0f s into the shift the lump cart is still hot: %.0f s to cool (saved %.0f)" % [elapsed, cool, saved_cool])
	for c2 in _wlg.final_checks(_world):
		_check(bool(c2[0]), String(c2[1]))
	_phases_done["C"] = true

# ── Z ────────────────────────────────────────────────────────────────────────

func _finish() -> void:
	if _world != null and is_instance_valid(_world):
		_wlg.restore()
		_world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_cleanup_files()
	var left : Array = []
	for p in [FACTORY_PATH, SAVE_PATH, FACTORY_B]:
		if AtomicFile.exists_any(p):
			left.append(p)
	_check(left.is_empty(), "Z1 the suite's slot files are gone %s" % str(left))
	var missing : Array = []
	for ph in PHASES:
		if not _phases_done.has(ph):
			missing.append(ph)
	_check(missing.is_empty(), "Z2 every phase ran to its last line %s" % (str(missing) if not missing.is_empty() else "(A, B, C)"))
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		if bus.has_meta("pending_save_name"):
			bus.remove_meta("pending_save_name")
		if bus.has_meta("pending_is_new_save"):
			bus.remove_meta("pending_is_new_save")
	_wlg.disarm()
	_done = true
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
