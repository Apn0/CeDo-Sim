extends Node
class_name LineFlow
## Auto-links placed machines into a running material line and simulates flow.
##
## LINKING: each machine's output port is connected to the NEAREST other
## machine's input port within MAX_LINK_DIST, and a PHYSICAL connector (a sloped
## gutter when material drops, a pipe when it must be carried/lifted) is drawn
## between them — the link is a real conduit, not just a logical edge.
##
## FLOW: head nodes (no upstream link) are fed at FEED_RATE with a WET, DIRTY
## sample of the nearest bale (its real moisture + dirt + polymer mix). Each
## machine then fights water and contamination per its MachineFlow process tags:
## washers take on water and strip dirt, dryers drive water off, float/optical
## sorters reject heavies and off-spec polymer, and the extruder (sink) melt-
## filters the last dirt + degasses, then grades the granulaat quality. All
## transfers use MaterialBatch's conserving ops, so the FULL ledger balances:
##   fed + water_added == granulaat + waste + dirt_removed + water_removed
##                        + poly_rejected + in-line
##
## v1 simplifications (flagged): counters reset when the layout changes; bulk-
## density side effects beyond water mass aren't modelled; discrete bale
## consumption is by mass draw, not per-sheet.

const MAX_LINK_DIST : float = 14.0
const FEED_RATE     : float = 8.0     # kg/s drawn from a bale sitting on the feed point
const FEED_DENSITY  : float = 320.0   # kg/m³ for the injected feed volume
const FEED_RADIUS   : float = 5.0     # a bale must sit within this of a head input to feed it
const DEFAULT_COMP  : Dictionary = {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}

# ── #145 PHYSICALIZED TRANSPORT ───────────────────────────────────────────────
# Material no longer teleports from machine to machine. A machine only conveys at
# its LIVE rotation speed (spin-up × rotor rpm), and every connector is a real
# delay-line that takes transit_time to cross — so feeding the head can never
# produce instant output at the sink. The PLC powers the line up downstream-first.
const SPIN_UP_S     : float = 2.5     # s for a powered machine's rotor to reach full speed
const PLC_STAGGER   : float = 1.0     # MAX s between machines powering up (downstream→upstream)
const TARGET_STARTUP_S : float = 20.0 # whole-line power-up is capped near this, however many machines
const TRANSPORT_MPS : float = 1.3     # how fast material rides a connector (m/s)
const PIPE_STAGES   : int   = 6       # delay-line resolution per connector
const MIN_TRANSIT_S : float = 0.6     # shortest connector still takes this long to cross
const PLCSequencerScript = preload("res://src/sim/PLCSequencer.gd")
const FloorPileScript    = preload("res://src/sim/FloorPile.gd")
const ProcessModelScript = preload("res://src/sim/ProcessModel.gd")
const Line3CDefScript    = preload("res://src/sim/Line3CDef.gd")

var _nodes : Array = []      # Array[Dictionary]
var _edges : Array = []      # Array[Dictionary] {a:int, b:int}
var _connectors : Node3D
var _ui    : CanvasLayer
var _label : Label

# The line only feeds from bales a VEHICLE HAS DROPPED at the feed machine
# (meta "delivered" = true). Bales merely placed in build mode are inert scenery
# and never feed. Each delivered bale is consumed (finite) and removed when empty.
var feed_enabled : bool = true

# #9 — overflow / emergency-stop. When a machine's input buffer backs up past
# OVERLOAD_KG (e.g. the flotation tank floods + the paddles stall), the line
# E-STOPs: the fault machine and EVERYTHING UPSTREAM stop instantly (feed off,
# rotors spin down), while DOWNSTREAM keeps running to empty itself (controlled).
# Auto-clears once the fault is relieved (crew) AND the downstream has drained.
const OVERLOAD_KG : float = 250.0          # ~2× the crew jam threshold (BUF-300 = 120)
var _estop_active : bool = false
var _estop_fault_order : int = -1          # flow-order position of the fault
var _estop_fault_node  : int = -1          # node index of the fault

# Cumulative since last rebuild (mass kg / volume m³)
var fed_mass := 0.0
var gran_mass := 0.0
var waste_mass := 0.0
# Wet/dirty side streams (kg) so the full ledger balances:
#   fed + water_added == granulaat + waste + contam_removed + water_removed
#                        + poly_rejected + in-line
var water_added    := 0.0    # process water drawn in by washers
var water_removed  := 0.0    # moisture driven off by dryers/dewaterers (effluent/vapour)
var contam_removed := 0.0    # dirt stripped to scraper bins
var poly_rejected  := 0.0    # off-spec polymer kicked out by optical/float sorters
# Granulaat quality (0..100), mass-weighted average over the run.
var _gran_q_accum  := 0.0

# ── #145 transport state ──────────────────────────────────────────────────────
# The PLC that powers the line up/down; _plc_stage_node maps each PLC stage index
# to its node index (head→tail order). auto_start powers the line on rebuild so
# the existing demo keeps running; a caller can set it false to stage a cold start.
var _plc            : Node  = null     # a PLCSequencer (typed as Node — version-safe)
var _plc_stage_node : Array = []
var auto_start      : bool  = true

# ── per-tick cache for performance ────────────────────────────────────────────
var _floor_piles_cache : Array = []
var _waste_containers_cache : Array = []

# =============================================================================
func _ready() -> void:
	_connectors = Node3D.new()
	_connectors.name = "Connectors"
	add_child(_connectors)
	_build_ui()
	rebuild()

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 38
	add_child(_ui)
	_label = Label.new()
	_label.anchor_left = 1.0
	_label.anchor_right = 1.0
	_label.offset_left = -320.0
	_label.offset_top = 70.0
	_label.offset_right = -12.0
	_label.add_theme_font_size_override("font_size", 13)
	_label.add_theme_color_override("font_color", Color(0.8, 1.0, 0.85))
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 5)
	_ui.add_child(_label)

# =============================================================================
# GRAPH
# =============================================================================
func rebuild() -> void:
	fed_mass = 0.0
	gran_mass = 0.0
	waste_mass = 0.0
	water_added = 0.0
	water_removed = 0.0
	contam_removed = 0.0
	poly_rejected = 0.0
	_gran_q_accum = 0.0
	_discover()
	_link()
	_init_pipes()       # #145: turn each link into a transit delay-line
	_init_plc()         # #145: stage the downstream-first power-up
	_spawn_connectors()
	print("[LineFlow] %d machines, %d links (transport physicalized)" % [_nodes.size(), _edges.size()])

## Mass-weighted average quality (0..100) of all granulaat produced this run.
func granulaat_quality() -> float:
	return _gran_q_accum / gran_mass if gran_mass > 0.0 else 0.0

func _discover() -> void:
	_nodes.clear()
	for m in get_tree().get_nodes_in_group("placed_object"):
		var node3d := m as Node3D
		if node3d == null or not node3d.has_meta("placeable_id"):
			continue
		# Waste containers / floor piles are SINKS for reject, not material-flow
		# process machines — never let them into the line topology even if a
		# build path tagged them placed_object.
		if node3d.is_in_group("waste_container") or node3d.is_in_group("floor_pile"):
			continue
		var id := String(node3d.get_meta("placeable_id"))
		var prof := MachineFlow.profile(id)
		if String(prof["role"]) == "none":
			continue
		var item := PlaceableCatalog.get_item(id)
		if item.is_empty():
			continue
		var size: Vector3 = item["size"]
		var inf: Vector3  = prof["in"]
		var outf: Vector3 = prof["out"]
		# Default physics = MachineFlow's generic per-id fractions. For a real
		# LINE 3C stage (tagged with its HMI code) we OVERRIDE them with the BAKED,
		# calibrated ProcessModel coefficients (#173) and seed its nominal current.
		var p_waste    : float = float(prof["waste"])
		var p_water_a  : float = float(prof["water_add"])
		var p_water_r  : float = float(prof["water_remove"])
		var p_contam_r : float = float(prof["contam_remove"])
		var p_rej_o    : float = float(prof["reject_other"])
		var p_rej_h    : float = float(prof["reject_hdpe"])
		var l3c_code   : String = String(node3d.get_meta("l3c_code")) if node3d.has_meta("l3c_code") else ""
		var amps_nom   : float = 0.0
		if l3c_code != "" and ProcessModelScript.has_stage(l3c_code):
			var tf : Dictionary = ProcessModelScript.stage_transfer(l3c_code)
			p_water_a  = float(tf["water_add"])
			p_water_r  = float(tf["water_remove"])
			p_contam_r = float(tf["contam_remove"])
			p_rej_o    = float(tf["reject_other"])
			p_rej_h    = float(tf["reject_hdpe"])
			p_waste    = float(tf["waste"])
			amps_nom   = ProcessModelScript.hmi_amps_for_code(l3c_code)
		_nodes.append({
			"node":  node3d,
			"id":    id,
			"role":  String(prof["role"]),
			"waste": p_waste,
			"rate":  float(prof["rate"]),
			"process":       String(prof["process"]),
			"water_add":     p_water_a,
			"water_remove":  p_water_r,
			"contam_remove": p_contam_r,
			"reject_other":  p_rej_o,
			"reject_hdpe":   p_rej_h,
			"l3c_code":      l3c_code,
			"amps_nominal":  amps_nom,
			"amps":          0.0,
			"win":   node3d.to_global(Vector3(inf.x * size.x, inf.y * size.y, inf.z * size.z)),
			"wout":  node3d.to_global(Vector3(outf.x * size.x, outf.y * size.y, outf.z * size.z)),
			"in":    MaterialBatch.new(),
			"out":   MaterialBatch.new(),
			# Live telemetry, refreshed each tick so the HMI can read real operator
			# numbers per machine (smoothed throughput; instantaneous stream state).
			"thru":    0.0,    # kg/s leaving this machine (EMA-smoothed)
			"moist":   0.0,    # % moisture of the stream leaving
			"contam":  0.0,    # % contamination of the stream leaving
			"quality": 0.0,    # 0..100 melt-quality grade of the stream leaving
			"buffer":  0.0,    # kg waiting in this machine's input buffer
			# #145 transport: the machine's conveying rotor (if it has one), its
			# live spin-up state (0..1), and whether the PLC has powered it.
			"mech":    _find_mechanism(node3d),
			"spin":    0.0,
			"powered": false,
			# Per-machine HMI override (#new-hmi). hand_mode bypasses the PLC and the
			# safeguards (upstream-empty, e-stop, shredder interlock) — manual_on then
			# decides whether the machine runs. component_pct stores per-component
			# RPM overrides (inlet/paddles/outlet for tanks; "drive" for conveyors /
			# ventilators / shredders); the effective rate is the design rate scaled
			# by the AVERAGE of these and by rpm_pct. Defaults run the machine 100%.
			"hand_mode":     false,
			"manual_on":     false,
			"rpm_pct":       1.0,
			"components":    _default_components_for(id),
			# #173 visual coupling: the machine's FilmFlakeField (if any), driven
			# each tick from this node's live telemetry so the look matches the sim.
			"view":    _find_film_field(node3d),
		})

func _link() -> void:
	_edges.clear()
	var n := _nodes.size()
	# Map Line 3C HMI codes → node index, so the explicit branch topology (#1) can
	# resolve its [from,to] edges. Lets one stage feed TWO downstream (a split) and
	# two stages feed ONE (a merge) — impossible with the old single-nearest linker.
	var code_idx : Dictionary = {}
	for i in n:
		var c : String = String(_nodes[i].get("l3c_code", ""))
		if c != "":
			code_idx[c] = i
	for i in n:
		var a: Dictionary = _nodes[i]
		if String(a["role"]) == "sink":
			continue                       # sinks consume, never feed downstream
		# 1) EXPLICIT topology for Line 3C stages (handles splits + merges).
		var code : String = String(a.get("l3c_code", ""))
		var linked_explicitly := false
		if code != "":
			for tc in Line3CDefScript.out_links(code):
				if code_idx.has(tc):
					var bi : int = int(code_idx[tc])
					if bi != i and not _edge_exists(i, bi):
						_edges.append({"a": i, "b": bi})
						linked_explicitly = true
			if linked_explicitly:
				continue   # this stage's downstream is fully defined by the graph
		# 2) GEOMETRY fallback (build-mode objects / other lines): single nearest input.
		var a_out: Vector3 = a["wout"]
		var best := -1
		var best_d := MAX_LINK_DIST
		for j in n:
			if j == i:
				continue
			var b: Dictionary = _nodes[j]
			var d := a_out.distance_to(b["win"] as Vector3)
			if d < best_d:
				best_d = d
				best = j
		# Skip if the chosen target already feeds us (avoids trivial 2-cycles).
		if best >= 0 and not _edge_exists(best, i):
			_edges.append({"a": i, "b": best})

func _edge_exists(a: int, b: int) -> bool:
	for e in _edges:
		if int(e["a"]) == a and int(e["b"]) == b:
			return true
	return false

func _has_incoming(idx: int) -> bool:
	for e in _edges:
		if int(e["b"]) == idx:
			return true
	return false

# ── #145 transport helpers ────────────────────────────────────────────────────
## The conveying rotor of a machine, if it has one: the first child in the
## "mechanism" group that exposes current_rpm() (a RotatingMechanism). null when
## the machine has no modelled rotor — those fall back to a spin-only gate.
func _find_mechanism(machine: Node) -> Node:
	for c in machine.get_children():
		if c.is_in_group("mechanism") and c.has_method("current_rpm"):
			return c
	return null

## The machine's FilmFlakeField visual layer (if it has one), for #173 coupling.
func _find_film_field(machine: Node) -> Node:
	for c in machine.get_children():
		if c.is_in_group("film_field") and c.has_method("set_live_state"):
			return c
	return null

## Live conveying fraction (0..1.25) from a node's rotor rpm vs its nominal. 1.0
## when the node has no rotor (the spin gate alone then governs it).
func _mech_fraction(nd: Dictionary) -> float:
	var mech = nd.get("mech")
	if mech == null or not is_instance_valid(mech):
		return 1.0
	if not ("nominal_rpm" in mech):
		return 1.0
	var nom : float = float(mech.nominal_rpm)
	if nom <= 0.0:
		return 1.0
	return clampf(float(mech.call("current_rpm")) / nom, 0.0, 1.25)

## Turn every link into a fixed-resolution delay-line: PIPE_STAGES MaterialBatch
## slots that shift forward one slot every stage_dt, so a parcel takes the whole
## transit_time (length ÷ transport speed) to cross. Bounded memory, conserving.
func _init_pipes() -> void:
	for e in _edges:
		var a: Dictionary = _nodes[int(e["a"])]
		var b: Dictionary = _nodes[int(e["b"])]
		var length: float = (a["wout"] as Vector3).distance_to(b["win"] as Vector3)
		var transit: float = maxf(length / TRANSPORT_MPS, MIN_TRANSIT_S)
		var pipe: Array = []
		for _s in PIPE_STAGES:
			pipe.append(MaterialBatch.new())
		e["pipe"]     = pipe
		e["len"]      = length
		e["stage_dt"] = transit / float(PIPE_STAGES)
		e["stage_t"]  = 0.0

## Build the PLC start sequencer in FLOW order (head→tail). PLCSequencer powers
## the LAST stage (the tail / sink) first and walks upstream, which is the real
## "give material somewhere to go before you start feeding it" power-up.
func _init_plc() -> void:
	_plc = PLCSequencerScript.new()
	_plc_stage_node = _flow_order()
	# Stagger per machine, but cap the whole-line power-up near TARGET_STARTUP_S so
	# a 100-machine line doesn't take 100 s to come up. Short lines keep the full
	# 1 s/stage feel; long lines compress toward the floor.
	_plc.stagger_s = clampf(TARGET_STARTUP_S / float(maxi(_plc_stage_node.size(), 1)), 0.15, PLC_STAGGER)
	for _i in _plc_stage_node:
		_plc.add_stage(null)
	for nd in _nodes:
		nd["powered"] = false
		nd["spin"]    = 0.0
	if auto_start:
		_plc.start()

## Topological head→tail ordering of the node indices (Kahn's algorithm over the
## directed links). Nodes caught in a cycle are appended last so they still power.
func _flow_order() -> Array:
	var n := _nodes.size()
	var indeg : Array = []
	indeg.resize(n)
	for i in n:
		indeg[i] = 0
	for e in _edges:
		indeg[int(e["b"])] = int(indeg[int(e["b"])]) + 1
	var queue : Array = []
	for i in n:
		if int(indeg[i]) == 0:
			queue.append(i)
	var order : Array = []
	while not queue.is_empty():
		var u : int = int(queue.pop_front())
		order.append(u)
		for e in _edges:
			if int(e["a"]) == u:
				var v : int = int(e["b"])
				indeg[v] = int(indeg[v]) - 1
				if int(indeg[v]) == 0:
					queue.append(v)
	if order.size() < n:
		for i in n:
			if i not in order:
				order.append(i)
	return order

# ── #145 line power control (for HMI / crew / tests) ──────────────────────────
func start_line() -> void:
	if _plc != null:
		_plc.start()

func stop_line() -> void:
	if _plc != null:
		_plc.stop()

func is_line_starting() -> bool:
	return _plc != null and _plc.is_busy()

# ── HMI per-machine override + RPM controls (#new-hmi) ────────────────────────
## The components a machine of this `id` exposes to the HMI as separate RPM
## sliders. Tanks have 4 (inlet/two transports/outlet); conveyors + ventilators
## + shredders have a single drive. Anything else falls back to "drive".
static func _default_components_for(id: String) -> Dictionary:
	var out := {}
	var lid := id.to_lower()
	if lid.find("flotation") >= 0 or lid.find("sink") >= 0 or lid.find("rotation_tank") >= 0:
		out["inlet"]       = 1.0
		out["transport_1"] = 1.0
		out["transport_2"] = 1.0
		out["outlet"]      = 1.0
	elif lid.find("blower") >= 0 or lid.find("ventilator") >= 0 or lid.find("cyclone") >= 0 or lid.find("sifter") >= 0:
		out["drive"] = 1.0
	elif lid.find("shredder") >= 0 or lid.find("mill") >= 0:
		out["rotor"] = 1.0
	else:
		out["drive"] = 1.0
	return out

## Lookup a machine node dict by its placeable id; returns the FIRST match (machines
## are unique per build). Empty dict if missing.
func _find_node_by_id(id: String) -> Dictionary:
	for nd in _nodes:
		if String(nd["id"]) == id:
			return nd
	return {}

## Public HMI surface — every setter quietly noops on an unknown id so the panel
## can be opened before the line has been built without crashing.
func set_machine_hand_mode(id: String, on: bool) -> void:
	var nd := _find_node_by_id(id)
	if not nd.is_empty():
		nd["hand_mode"] = on
		if not on:
			nd["manual_on"] = false   # leaving HAND drops the manual run

func set_machine_manual_on(id: String, on: bool) -> void:
	var nd := _find_node_by_id(id)
	if not nd.is_empty() and bool(nd["hand_mode"]):
		nd["manual_on"] = on

func set_machine_rpm_pct(id: String, pct: float) -> void:
	var nd := _find_node_by_id(id)
	if not nd.is_empty():
		nd["rpm_pct"] = clampf(pct, 0.0, 2.0)

func set_machine_component_pct(id: String, component: String, pct: float) -> void:
	var nd := _find_node_by_id(id)
	if nd.is_empty():
		return
	var c : Dictionary = nd["components"]
	if c.has(component):
		c[component] = clampf(pct, 0.0, 2.0)

## Returns a snapshot the HMI can render: live state + override state + components.
func get_machine_info(id: String) -> Dictionary:
	var nd := _find_node_by_id(id)
	if nd.is_empty():
		return {}
	return {
		"id":         String(nd["id"]),
		"role":       String(nd["role"]),
		"process":    String(nd["process"]),
		"rate":       float(nd["rate"]),
		"spin":       float(nd["spin"]),
		"powered":    bool(nd["powered"]),
		"buffer":     float(nd["buffer"]),
		"thru":       float(nd["thru"]),
		"moist":      float(nd["moist"]),
		"contam":     float(nd["contam"]),
		"quality":    float(nd["quality"]),
		"amps":       float(nd["amps"]),
		"hand_mode":  bool(nd.get("hand_mode", false)),
		"manual_on":  bool(nd.get("manual_on", false)),
		"rpm_pct":    float(nd.get("rpm_pct", 1.0)),
		"components": (nd.get("components", {}) as Dictionary).duplicate(),
	}

## Every machine on the line as a flat list for the MACHINES screen list.
func machine_list() -> Array:
	var out : Array = []
	for nd in _nodes:
		out.append({
			"id":      String(nd["id"]),
			"role":    String(nd["role"]),
			"process": String(nd["process"]),
		})
	return out

## Average of a node's component_pct entries (1.0 if none) — used by the eff_rate
## calc in the tick to scale design rate by the operator's per-component settings.
func _component_pct_avg(nd: Dictionary) -> float:
	var c : Dictionary = nd.get("components", {})
	if c.is_empty():
		return 1.0
	var s := 0.0
	for k in c:
		s += float(c[k])
	return s / float(c.size())

# ── #9 overflow / emergency-stop ───────────────────────────────────────────────
func is_estopped() -> bool:
	return _estop_active

func estop_fault_id() -> String:
	if _estop_active and _estop_fault_node >= 0 and _estop_fault_node < _nodes.size():
		return String(_nodes[_estop_fault_node].get("id", "?"))
	return ""

## Run each tick (after the PLC powers the line): detect an overload, enforce the
## upstream stop, and auto-clear once it's safe again.
func _estop_step() -> void:
	if _estop_active:
		# Recovery: fault relieved (crew unchoked it) AND downstream emptied.
		var fault_buf := 0.0
		if _estop_fault_node >= 0 and _estop_fault_node < _nodes.size():
			fault_buf = float(_nodes[_estop_fault_node].get("buffer", 0.0))
		if fault_buf < OVERLOAD_KG * 0.5 and _downstream_transit(_estop_fault_order) < 1.0:
			_clear_estop()
	else:
		# Detection: trip on the first machine whose input buffer is past OVERLOAD_KG.
		for stage in _plc_stage_node.size():
			var ni : int = int(_plc_stage_node[stage])
			if float(_nodes[ni].get("buffer", 0.0)) > OVERLOAD_KG:
				_trigger_estop(stage, ni)
				break
	# Enforce: while tripped, kill the feed + the fault and everything UPSTREAM of
	# it; the downstream keeps its PLC power so it runs on and empties.
	if _estop_active:
		feed_enabled = false
		for stage in _plc_stage_node.size():
			if stage <= _estop_fault_order:
				_nodes[int(_plc_stage_node[stage])]["powered"] = false

func _trigger_estop(fault_order: int, fault_node: int) -> void:
	_estop_active = true
	_estop_fault_order = fault_order
	_estop_fault_node = fault_node
	feed_enabled = false
	var fid := String(_nodes[fault_node].get("id", "?"))
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("machine_alarm_raised"):
		bus.emit_signal("machine_alarm_raised", fid, "OVERLOAD-ESTOP", 3)
	print("[LineFlow] E-STOP: overload at '%s' — upstream stopped, downstream emptying." % fid)

func _clear_estop() -> void:
	var fid := estop_fault_id()
	_estop_active = false
	_estop_fault_order = -1
	_estop_fault_node = -1
	feed_enabled = true        # safe + drained → resume
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("machine_alarm_cleared"):
		bus.emit_signal("machine_alarm_cleared", fid, "OVERLOAD-ESTOP")
	print("[LineFlow] E-STOP cleared — line resuming.")

## Total mass (buffers + connectors) strictly DOWNSTREAM of the fault — the line
## is "empty" downstream once this falls near zero.
func _downstream_transit(fault_order: int) -> float:
	var m := 0.0
	for stage in range(fault_order + 1, _plc_stage_node.size()):
		m += float(_nodes[int(_plc_stage_node[stage])].get("buffer", 0.0))
	for e in _edges:
		if _plc_stage_node.find(int(e["a"])) > fault_order:
			for st in (e["pipe"] as Array):
				m += (st as MaterialBatch).mass_kg
	return m

## Fraction of machines currently powered (0..1) — for the HMI line-status banner.
func line_powered_fraction() -> float:
	if _plc == null or _plc_stage_node.is_empty():
		return 0.0
	return float(_plc.powered_count()) / float(_plc_stage_node.size())

## Total mass currently riding the connectors (in transit between machines).
func pipe_mass() -> float:
	var m := 0.0
	for e in _edges:
		for st in (e["pipe"] as Array):
			m += (st as MaterialBatch).mass_kg
	return m

## Total live current (A) the whole line is drawing right now — the sum of every
## metered stage's calibrated draw (#173). Reads ~488 A at full Line 3C load.
func live_line_amps() -> float:
	var a := 0.0
	for nd in _nodes:
		a += float(nd.get("amps", 0.0))
	return a

## Total mass still inside machine buffers + on connectors (not yet output).
func in_transit_mass() -> float:
	var m := 0.0
	for nd in _nodes:
		m += (nd["in"] as MaterialBatch).mass_kg
		m += (nd["out"] as MaterialBatch).mass_kg
	return m + pipe_mass()

## Conservation residual (kg): in (fed + process water) − out (granulaat + waste +
## dirt + water removed + poly rejected) − still-in-line. → 0 means nothing was
## silently created or destroyed, now including material riding the connectors.
func ledger_residual() -> float:
	return fed_mass + water_added \
		- gran_mass - waste_mass - contam_removed - water_removed - poly_rejected \
		- in_transit_mass()

# =============================================================================
# FLOW TICK
# =============================================================================
func _process(delta: float) -> void:
	tick(delta)

## The flow step. Split out from _process so a headless test can drive it with a
## FIXED delta — deterministic sim time, independent of engine frame pacing (the
## same pattern CrewManager.tick() uses).
func tick(delta: float) -> void:
	if _nodes.is_empty():
		_update_label()
		return

	# Cache spatial queries once per tick for heavy inner loops like _dump_waste
	var tree = get_tree()
	if tree != null:
		_floor_piles_cache = tree.get_nodes_in_group("floor_pile")
		_waste_containers_cache = tree.get_nodes_in_group("waste_container")
	else:
		_floor_piles_cache.clear()
		_waste_containers_cache.clear()

	# 0) PLC powers the line up DOWNSTREAM-FIRST; each powered machine then ramps
	#    its rotor over SPIN_UP_S. The live spin (0..1) gates how fast it conveys,
	#    so nothing moves until the rotor is actually turning (#145).
	if _plc != null:
		_plc.tick(delta)
		for stage in _plc_stage_node.size():
			var ni : int = int(_plc_stage_node[stage])
			_nodes[ni]["powered"] = _plc.is_powered(stage)
	# HMI HAND-mode override (#new-hmi): when the operator has switched a machine to
	# HAND on the per-machine HMI screen, the PLC + safeguards are BYPASSED for that
	# machine — `manual_on` directly drives powered. Operator's responsibility (the
	# panel shows a warning lamp + amber stripe to make that explicit).
	for nd_h in _nodes:
		if bool(nd_h.get("hand_mode", false)):
			nd_h["powered"] = bool(nd_h.get("manual_on", false))
	# #9 — overflow/e-stop override: trip on an overloaded buffer, then force the
	# fault + upstream OFF (downstream keeps its PLC power and drains).
	_estop_step()
	for nd_s in _nodes:
		var tgt : float = 1.0 if bool(nd_s["powered"]) else 0.0
		nd_s["spin"] = move_toward(float(nd_s["spin"]), tgt, delta / maxf(SPIN_UP_S, 0.01))
		var mech_s = nd_s.get("mech")
		if mech_s != null and is_instance_valid(mech_s) and mech_s.has_method("set_running"):
			mech_s.call("set_running", bool(nd_s["powered"]))
		# Live current (#173): a stage draws its full HMI amps at full material
		# load, sags to the motor idle current when starved, and 0 when stopped.
		# Load is gauged against the machine's OWN design rate (self-consistent).
		var rate_s : float = float(nd_s["rate"])
		var load_s : float = clampf(float(nd_s["thru"]) / rate_s, 0.0, 1.25) if rate_s > 0.0 else 0.0
		nd_s["amps"] = ProcessModelScript.stage_amps(
			float(nd_s["amps_nominal"]), load_s, float(nd_s["spin"]) > 0.1)
		# Drive the visual flake layer from the live state (#173): material present
		# → flake density, throughput → drift speed, moisture/contam → wet/dirty look.
		var view_s = nd_s.get("view")
		if view_s != null and is_instance_valid(view_s):
			view_s.call("set_live_state", load_s,
				clampf(float(nd_s["moist"]) / 40.0, 0.0, 1.0),
				clampf(float(nd_s["contam"]) / 15.0, 0.0, 1.0),
				clampf(float(nd_s["buffer"]) / 40.0, 0.0, 1.0))

	# 1) Feed — OFF unless deliberately enabled. When on, a head node draws from a
	#    bale on its feed point and DEPLETES that bale (finite); the bale is removed
	#    when empty, so the line can never feed from thin air or forever.
	if feed_enabled:
		var bales := get_tree().get_nodes_in_group("bale")
		for i in _nodes.size():
			var nd: Dictionary = _nodes[i]
			if String(nd["role"]) == "sink" or _has_incoming(i):
				continue
			var bale := _bale_at((nd["node"] as Node3D).global_position, bales)
			if bale == null:
				continue
			var remaining := _bale_remaining(bale)
			if remaining <= 0.0:
				continue
			var draw := minf(FEED_RATE * delta, remaining)
			# Inject a WET, DIRTY sample at the bale's real moisture/dirt/mix — the
			# line head receives exactly what the wash+dry+sort train must clean up.
			var sample := BaleDefs.feed_sample(String(bale.get_meta("material_origin")), draw)
			if sample.is_empty():
				sample = MaterialBatch.new(draw, draw / FEED_DENSITY, DEFAULT_COMP.duplicate(), "feed",
										   draw * 0.08, draw * 0.12)
			(nd["in"] as MaterialBatch).add(sample)
			fed_mass += draw
			remaining -= draw
			bale.set_meta("remaining_kg", remaining)
			if remaining <= 0.0:
				bale.queue_free()

	# 2) Each machine processes up to rate·delta. It fights water + dirt in the
	#    same order a real line does: strip contaminant → sort off-spec → drive
	#    water off / take water on → shed mechanical yield loss. The extruder
	#    (sink) does the last melt-filter + degas and grades the granulaat.
	var dt := maxf(delta, 0.0001)
	for nd in _nodes:
		var bin: MaterialBatch = nd["in"]
		nd["buffer"] = bin.mass_kg
		if bin.mass_kg <= 0.0:
			nd["thru"] = lerpf(float(nd["thru"]), 0.0, 0.2)   # spin down when starved
			continue
		# Effective conveying rate is GATED by live rotation: design rate × spin-up
		# × rotor rpm-fraction. A stopped or still-spinning-up rotor moves nothing,
		# so material backs up in this machine's input buffer (#145).
		# Effective rate = design × spin × mech × HMI overrides (rpm slider AND the
		# avg of the per-component RPMs — inlet/transports/outlet for tanks).
		var rate_mul : float = float(nd.get("rpm_pct", 1.0)) * _component_pct_avg(nd)
		var eff_rate: float = float(nd["rate"]) * float(nd["spin"]) * _mech_fraction(nd) * rate_mul
		if eff_rate <= 0.0001:
			nd["thru"] = lerpf(float(nd["thru"]), 0.0, 0.2)
			continue
		var flow := bin.split_mass(minf(eff_rate * delta, bin.mass_kg))

		# a) contaminant stripped out → nearest scraper bin (DIRT stream)
		var cr: float = nd["contam_remove"]
		if cr > 0.0:
			var dirt := flow.remove_contaminant(cr)
			if dirt > 0.0:
				contam_removed += dirt
				_dump_waste(nd["wout"] as Vector3, _dirt_batch(dirt), _waste_containers_cache, 2)   # Stream.DIRT

		# b) off-spec polymer rejected (optical/float sort) → reject stream
		var ro: float = nd["reject_other"]
		if ro > 0.0:
			poly_rejected += flow.reject_polymer("other", ro)
		var rh: float = nd["reject_hdpe"]
		if rh > 0.0:
			poly_rejected += flow.reject_polymer("HDPE", rh)

		# c) drying drives water off (to effluent / vapour)
		var wr: float = nd["water_remove"]
		if wr > 0.0:
			water_removed += flow.remove_water(wr)

		# d) washing takes process water on (raises moisture + bulk)
		var wa: float = nd["water_add"]
		if wa > 0.0:
			var added := flow.polymer_kg() * wa
			flow.add_water(added)
			water_added += added

		# e) mechanical yield loss — a true loss of polymer mass → waste container.
		# Classify by machine role: washers/screens shed FINES, sorters shed
		# COARSE_FILM, cyclones shed SLUDGE. Default = COARSE_FILM (the catch-all).
		var wfrac: float = nd["waste"]
		if wfrac > 0.0:
			var w := flow.split_fraction(wfrac)
			waste_mass += w.mass_kg
			_dump_waste(nd["wout"] as Vector3, w, _waste_containers_cache, _waste_stream_for_role(String(nd["role"]), String(nd["process"])))

		# Live telemetry: smoothed output rate + a snapshot of what's leaving, so the
		# HMI shows real per-machine moisture / dirt / quality, not just kg in buffer.
		nd["thru"]    = lerpf(float(nd["thru"]), flow.mass_kg / dt, 0.25)
		nd["moist"]   = flow.moisture_pct()
		nd["contam"]  = flow.contam_pct()
		nd["quality"] = flow.quality_grade()

		# f) sink banks the granulaat + its quality; everything else passes on
		if String(nd["role"]) == "sink":
			gran_mass += flow.mass_kg
			_gran_q_accum += flow.quality_grade() * flow.mass_kg
		else:
			(nd["out"] as MaterialBatch).add(flow)

	# 3) Carry each output DOWN ITS CONNECTOR as a delay-line. Material entering a
	#    link rides PIPE_STAGES slots that shift forward one slot every stage_dt,
	#    so it takes the full transit_time to reach the downstream machine. Feeding
	#    the head therefore CANNOT appear instantly at the sink (#145).
	# Pre-count each source's outgoing edges so a SPLIT divides its output EVENLY
	# across the branches (otherwise the first edge took everything). Conserving:
	# the shares sum back to the original, and merges re-sum at the downstream input.
	var _out_left : Dictionary = {}
	for e2 in _edges:
		var ai2 := int(e2["a"])
		_out_left[ai2] = int(_out_left.get(ai2, 0)) + 1
	for e in _edges:
		var an: Dictionary = _nodes[int(e["a"])]
		var bn: Dictionary = _nodes[int(e["b"])]
		var pipe: Array = e["pipe"]
		var src := int(e["a"])
		var rem : int = int(_out_left[src])
		# Inject this branch's SHARE of the source's output into the entry slot.
		var aout: MaterialBatch = an["out"]
		if aout.mass_kg > 0.0 and rem > 0:
			if rem <= 1:
				(pipe[0] as MaterialBatch).add(aout)          # last/only branch takes the rest
				an["out"] = MaterialBatch.new()
			else:
				(pipe[0] as MaterialBatch).add(aout.split_fraction(1.0 / float(rem)))
		_out_left[src] = rem - 1
		# Advance the belt: shift slots forward whenever a stage interval elapses.
		e["stage_t"] = float(e["stage_t"]) + delta
		var guard := 0
		while float(e["stage_t"]) >= float(e["stage_dt"]) and guard < PIPE_STAGES * 4:
			e["stage_t"] = float(e["stage_t"]) - float(e["stage_dt"])
			guard += 1
			var tail: MaterialBatch = pipe[pipe.size() - 1]
			if tail.mass_kg > 0.0:
				(bn["in"] as MaterialBatch).add(tail)   # delivered to downstream input
			for s in range(pipe.size() - 1, 0, -1):
				pipe[s] = pipe[s - 1]
			pipe[0] = MaterialBatch.new()

	_update_label()

## Remaining material in a bale (kg). Initialised from its weight on first use.
func _bale_remaining(bale: Node3D) -> float:
	if bale.has_meta("remaining_kg"):
		return float(bale.get_meta("remaining_kg"))
	var w := 350.0
	if bale.has_meta("material_origin"):
		var item := PlaceableCatalog.get_item(String(bale.get_meta("material_origin")))
		if not item.is_empty():
			w = BaleDefs.estimated_weight(item["size"] as Vector3)
	bale.set_meta("remaining_kg", w)
	return w

## Returns the nearest bale within FEED_RADIUS of a feed point, or null.
func _bale_at(pos: Vector3, bales: Array[Node] = []) -> Node3D:
	var best : Node3D = null
	var best_d := FEED_RADIUS
	if bales.is_empty():
		bales = get_tree().get_nodes_in_group("bale")
	for c in bales:
		var cn := c as Node3D
		if cn == null or not cn.has_meta("material_origin"):
			continue
		if not (cn.has_meta("delivered") and bool(cn.get_meta("delivered"))):
			continue   # only vehicle-delivered bales feed the line
		var d := cn.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = cn
	return best

## Route a waste batch to the nearest compatible WasteContainer. The container's
## API now models capacity + density + overflow; if no stream-specific bin is in
## range OR it's full and refuses the rest, we fall back to the nearest catch-all
## bin (a container with no accepted_streams filter). Anything still unaccepted
## is currently dropped on the floor as a counter — Wave 5 will turn that into
## a visible floor pile.
func _dump_waste(pos: Vector3, w: MaterialBatch, containers: Array, cls: int = -1) -> void:
	if w.mass_kg <= 0.0:
		return
	var stream_specific : Node = _nearest_container(pos, cls, true, containers)
	var leftover : float = w.mass_kg
	if stream_specific != null:
		leftover = stream_specific.call("add", w.mass_kg, _stream_density(cls), cls)
	if leftover > 0.0:
		# Try a catch-all (no accepted_streams filter) for the overflow.
		var catch_all : Node = _nearest_container(pos, cls, false, containers)
		if catch_all != null and catch_all != stream_specific:
			leftover = catch_all.call("add", leftover, _stream_density(cls), cls)
	if leftover > 0.0:
		# No bin caught it — the reject spills onto the floor. Use a pile already
		# under this chute if one exists; otherwise SPAWN one right here (#154), so
		# an uncaught chute visibly heaps up instead of vanishing. The operator then
		# shovels it (ShovelTool) or parks a container under the chute to catch it.
		var pile : Node = _nearest_floor_pile(pos)
		if pile == null:
			pile = _spawn_chute_pile(pos, cls)
		if pile != null:
			leftover = pile.call("add", leftover, _stream_density(cls))
	# Anything still rejected (pile maxed too) is silently lost at this layer — the
	# waste_mass counter at the call site keeps the ledger.
	pass

## #154 — drop a fresh FloorPile directly under a chute mouth that nothing is
## catching. Coloured by stream so reject heaps read differently (dirt vs film).
func _spawn_chute_pile(pos: Vector3, cls: int) -> Node:
	var pile = FloorPileScript.new()
	pile.name = "ChuteSpill"
	pile.max_radius_m = 2.5
	pile.pile_color = _stream_color(cls)
	var root : Node = get_tree().current_scene
	if root == null:
		root = self
	root.add_child(pile)
	var ground := pos
	ground.y = _floor_y_below(pos)
	(pile as Node3D).global_position = ground
	return pile

## Floor height directly below `pos` (raycast down up to 40 m). Falls back to
## 1 m below the chute when nothing is hit (e.g. headless with no floor body).
func _floor_y_below(pos: Vector3) -> float:
	# LineFlow is a plain Node, so reach the 3-D world via the tree's root viewport.
	var tree := get_tree()
	if tree != null and tree.root != null:
		var world : World3D = tree.root.find_world_3d()
		if world != null and world.direct_space_state != null:
			var q := PhysicsRayQueryParameters3D.create(pos + Vector3(0, 0.5, 0), pos + Vector3(0, -40.0, 0))
			var hit := world.direct_space_state.intersect_ray(q)
			if hit.has("position"):
				return float((hit["position"] as Vector3).y)
	return pos.y - 1.0

## A pile tint per waste stream class (mirrors the WasteContainer mound colours).
func _stream_color(cls: int) -> Color:
	match cls:
		0: return Color(0.48, 0.45, 0.40)   # COARSE_FILM
		1: return Color(0.55, 0.52, 0.45)   # FINES
		2: return Color(0.34, 0.28, 0.22)   # DIRT
		4: return Color(0.32, 0.30, 0.26)   # SLUDGE
		6: return Color(0.40, 0.42, 0.48)   # POLY_REJECT
	return Color(0.45, 0.43, 0.40)

## Nearest FloorPile to `pos` within a generous 40 m. Used as final spillover sink
## for waste mass that no WasteContainer can accept.
func _nearest_floor_pile(pos: Vector3) -> Node:
	var best : Node = null
	var best_d := 40.0
	for p in _floor_piles_cache:
		var pn := p as Node3D
		if pn == null:
			continue
		var d := pn.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = pn
	return best

## Find the nearest WasteContainer to `pos`. When `stream_specific` is true we
## only accept containers whose `accepted_streams` list explicitly includes cls
## (so a "FINES" bin won't catch our SLUDGE). When false we return the nearest
## catch-all (empty accepted_streams) for fallback routing.
func _nearest_container(pos: Vector3, cls: int, stream_specific: bool, containers: Array) -> Node:
	var best : Node = null
	var best_d := 40.0
	for c in _waste_containers_cache:
		var cn := c as Node3D
		if cn == null:
			continue
		var accepts: Array = cn.get("accepted_streams") if cn != null else []
		if stream_specific:
			if cls < 0 or accepts.is_empty() or cls not in accepts:
				continue
		else:
			if not accepts.is_empty():
				continue
		var d := cn.global_position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = cn
	return best

## Default bulk density (kg/m³) per stream class — used when LineFlow knows the
## stream but the container hasn't blended a density yet.
func _stream_density(cls: int) -> float:
	# Mirrors WasteContainer.Stream — see that enum for the canonical values.
	match cls:
		0: return 90.0      # COARSE_FILM  — light bagged film reject
		1: return 180.0     # FINES        — shredded fibres
		2: return 1400.0    # DIRT         — sand / organics in scraper bin
		3: return 4500.0    # METAL        — overband magnet collect
		4: return 800.0     # SLUDGE       — wet cyclone underflow
		5: return 1000.0    # EFFLUENT     — process water
		6: return 250.0     # POLY_REJECT  — off-spec polymer flakes
	return 200.0

## A pure-dirt waste batch (sand/organics ≈ 1400 kg/m³) for scraper-bin dumping.
func _dirt_batch(kg: float) -> MaterialBatch:
	return MaterialBatch.new(kg, kg / 1400.0, {"dirt": 1.0}, "reject", 0.0, kg)

## Map a machine's role + process tag to a WasteContainer.Stream value (int).
## Wash + screen residue = FINES; cyclones / dryers / dewaterers = SLUDGE; sorters
## kick out COARSE_FILM; everything else falls into COARSE_FILM as the catch-all.
func _waste_stream_for_role(role: String, process: String) -> int:
	if process.find("wash") >= 0 or process.find("screen") >= 0:
		return 1   # FINES
	if process.find("cyclone") >= 0 or process.find("dry") >= 0 or process.find("dewater") >= 0:
		return 4   # SLUDGE
	if role == "sorter" or process.find("sort") >= 0:
		return 0   # COARSE_FILM
	return 0       # COARSE_FILM (catch-all)

# =============================================================================
# PHYSICAL CONNECTORS
# =============================================================================
func _spawn_connectors() -> void:
	for c in _connectors.get_children():
		c.queue_free()
	for e in _edges:
		var a: Dictionary = _nodes[int(e["a"])]
		var b: Dictionary = _nodes[int(e["b"])]
		_make_connector(a["wout"] as Vector3, b["win"] as Vector3)

func _make_connector(a_world: Vector3, b_world: Vector3) -> void:
	var dir := b_world - a_world
	var length := dir.length()
	if length < 0.05:
		return
	var mid := (a_world + b_world) * 0.5
	var drop := a_world.y - b_world.y
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.4
	mat.roughness = 0.5
	var mi := MeshInstance3D.new()
	var which := "y"
	if drop > 0.4:
		# gravity gutter: a shallow trough (its length runs along local Z)
		mat.albedo_color = Color(0.56, 0.56, 0.60)
		var bm := BoxMesh.new()
		bm.size = Vector3(0.45, 0.12, length)
		mi.mesh = bm
		which = "z"
	else:
		# pipe / pneumatic / screw run (cylinder along local Y)
		mat.albedo_color = Color(0.50, 0.53, 0.58)
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.12
		cm.height = length
		cm.radial_segments = 12
		mi.mesh = cm
	mi.material_override = mat
	_connectors.add_child(mi)
	mi.global_transform = Transform3D(_basis_along(dir, which), mid)
	mi.create_convex_collision()   # #10 — pipes/gutters are solid (no walking through)

func _basis_along(axis_world: Vector3, which: String) -> Basis:
	var n := axis_world.normalized()
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var b := Basis()
	if which == "y":
		var x := up.cross(n).normalized()
		b.x = x
		b.y = n
		b.z = x.cross(n).normalized()
	else:
		var x2 := up.cross(n).normalized()
		b.x = x2
		b.y = n.cross(x2).normalized()
		b.z = n
	return b.orthonormalized()

# =============================================================================
func _update_label() -> void:
	if _label == null:
		return
	if _nodes.is_empty():
		_label.text = ""
		return
	var in_transit := 0.0
	for nd in _nodes:
		in_transit += (nd["in"] as MaterialBatch).mass_kg
		in_transit += (nd["out"] as MaterialBatch).mass_kg
	in_transit += pipe_mass()    # #145: material riding the connectors counts too
	# Full ledger: what came IN (fed + process water) must equal what went OUT
	# (granulaat + mechanical waste + dirt scraped + water driven off + polymer
	# rejected) plus what's still travelling the line. residual → 0 means nothing
	# was silently created or destroyed.
	var residual := fed_mass + water_added \
		- gran_mass - waste_mass - contam_removed - water_removed - poly_rejected - in_transit
	_label.text = "LINE FLOW  ·  %d machines / %d links\n" % [_nodes.size(), _edges.size()] \
		+ "fed: %.0f kg   (+H2O in: %.0f kg)\n" % [fed_mass, water_added] \
		+ "granulaat: %.0f kg  ·  quality %.0f/100\n" % [gran_mass, granulaat_quality()] \
		+ "waste: %.0f kg   dirt out: %.0f kg\n" % [waste_mass, contam_removed] \
		+ "H2O out: %.0f kg   reject poly: %.0f kg\n" % [water_removed, poly_rejected] \
		+ "in line: %.0f kg   balance err: %.2f kg" % [in_transit, residual]
