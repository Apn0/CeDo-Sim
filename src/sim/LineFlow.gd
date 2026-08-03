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

## Emitted by BuildMode when an OBSERVER (HMI, decoration) is placed.
## Panel binders + topology-aware UI re-resolve their bindings via this
## without forcing a rebuild() that would destroy node state.
signal observer_placed(placeable_id : String)

const MAX_LINK_DIST : float = 14.0
const FEED_RATE     : float = 8.0     # kg/s drawn from a bale sitting on the feed point
const FEED_DENSITY  : float = 320.0   # kg/m³ for the injected feed volume
const FEED_RADIUS   : float = 5.0     # a bale must sit within this of a head input to feed it
# #24 — a head node may use the nearest WorldLayout.line_starts marker as its
# feed point instead of its own world position. The marker must sit within this
# radius of the head node to count as that line's intake marker. Larger than
# FEED_RADIUS so the user can place the marker reasonably far from the actual
# head machine and still have it wired (typical bale-yard → opzetband layout has
# 10-15 m between where bales drop and where the first machine sits).
const LINE_START_MARKER_RADIUS : float = 25.0
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
# #97 — buffer-aware splitter routing. A splitter (switch_belt) weights each of
# its two downstreams by remaining HEADROOM = 1 - buffer/CAP, so an empty silo
# pulls more than a near-full one. CAP is the buffer level at which the share
# falls to the eps floor (effectively "stop sending here"); EPS keeps the
# splitter alive when both downstreams are saturated (falls back to ~even split
# because two equal-eps weights normalise to 50/50).
const SPLITTER_CAPACITY_KG : float = 200.0
const SPLITTER_SHARE_EPS   : float = 0.01
const PLCSequencerScript = preload("res://src/sim/PLCSequencer.gd")
const FloorPileScript    = preload("res://src/sim/FloorPile.gd")
const ProcessModelScript = preload("res://src/sim/ProcessModel.gd")
const Line3CDefScript    = preload("res://src/sim/Line3CDef.gd")
const SwitchBeltScript   = preload("res://src/sim/SwitchBelt.gd")   # #137
const Conveyor8Script    = preload("res://src/sim/Conveyor8.gd")    # #138
# #138 — VSS buffer over this fraction-of-capacity counts as "FULL" for the
# overflow trip. When BOTH VSS_3A and VSS_3B are over this, C8 reverses.
const VSS_FULL_KG       : float = 150.0
# ── #52 advanced-systems OBSERVERS (additive, conserving) ─────────────────────
# These pure-sim modules run ALONGSIDE the material flow purely as observers: the
# extruder thermal/rheology + MFI soft-sensor publish telemetry, the motor-overload
# model can stop a jammed rotor conveying (mass just backs up — conserving), and the
# air network gates air-driven consumers' rate gently (slowing flow, never dropping
# mass). None of them re-route material, change the split math, or touch the
# CutterCompactor's transform.
const ExtruderScrewScript   = preload("res://src/sim/ExtruderScrew.gd")
const MfiProxyScript        = preload("res://src/sim/MfiProxy.gd")
const MotorOverloadScript   = preload("res://src/sim/MotorOverload.gd")
const CutterCompactorScript = preload("res://src/sim/CutterCompactor.gd")
# TITECH/TOMRA fibrous shaft-wrap fault state. Per-sorter controller; ticks the
# wrap accumulator with the moved throughput each frame, slows eff_rate once
# tripping, raises a SHAFT-WRAP alarm, and exposes cut_wrap() to the wire-cutter
# interaction (TitechShaftCut). One controller per placed NIR sorter, kept in
# the node dict under the "nir_ctrl" key.
const NirSorterScript       = preload("res://src/sim/NirSorter.gd")
# #99 — DRD batch dryer controller. The L+R mech_dryers run as a coordinated PAIR:
# one fills (BEFULLEN) while the other dries (TROCKNEN ~30s); 100% of upstream
# material is routed to whichever drum is currently in BEFULLEN. The pair starts
# 180° antiphase so a fresh drum is always accepting flake.
const MechDryerCycleScript  = preload("res://src/sim/MechDryerCycle.gd")
const MechDryerModelScript  = preload("res://src/sim/MechDryerModel.gd")
# A spinning extruder screw's max rpm (ExtruderScrew.SCREW_RPM_MAX); rpm_pct scales it.
const EXTRUDER_SCREW_MAX_RPM : float = 200.0
# The cutter-compactor's NOMINAL_RPM (see CutterCompactor.gd) — rpm_pct scales it.
const CC_NOMINAL_RPM         : float = 1500.0

var _nodes : Array = []      # Array[Dictionary]
var _edges : Array = []      # Array[Dictionary] {a:int, b:int}
var _connectors : Node3D
var _ui    : CanvasLayer
var _label : Label

# #A3 — per-rebuild lookup: target node3d → its SiloLevelSensor (if any). Used
# by the per-edge delivery loop to ask each silo's sensor for its feed
# multiplier this tick (normal cruise → 1.0, governor active → 0.0 closes the
# damper, bridged → 1.5 surge until overflow). Populated once per rebuild from
# the "silo_level_sensor" group; refreshed lazily when a sensor's silo_path
# resolves late. Empty when no sensor is placed on the line — every multiplier
# defaults to 1.0 so the wiring is a no-op for un-sensored silos.
var _silo_sensor_by_node : Dictionary = {}

# ── PER-INSTANCE ADDRESSING ───────────────────────────────────────────────────
# A placeable id is a machine TYPE ("friction_sep"), not an address: Line 3C
# alone runs five of them at four different calibrated currents. Every node
# therefore carries nd["key"], minted in _discover():
#   * the node's l3c_code when it is a stamped Line 3C stage ("L3C.9R") — the
#     operator's own plant address, so a front-end never has to invent one;
#   * otherwise "<placeable_id>#<n>", n counting instances of that id in
#     discovery order.
# NOT PERSISTED, and that is a measured decision rather than an oversight:
# nothing in the repo stores a machine handle across a save (HmiOverlay's
# selection is a session var, GameState.save_machine_state has zero callers), so
# the key only has to be stable between two rebuild()s. The day any feature
# persists a handle — a saved HMI favourite, a per-machine maintenance log — the
# ordinal half of this scheme has to become a minted, persisted uid.
#
# Codes REFUSED because another node already claimed them, as
# {code, kept, refused}. Non-empty means two nodes tried to be the same plant
# unit (two line_3c macros placed in one world); the later claimant loses its
# code and falls back to an ordinal key, so LineFlow's code_idx
# (:981-985, a first-match map) can never silently drop an edge.
var _code_conflicts : Array[Dictionary] = []

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
## When true, PLCSequencer.start() fires immediately after rebuild() and
## walks the line tail-to-head, powering each node on stagger_s apart.
## Defaults to FALSE — operator must press START on the HMI to begin
## production. The save loader flips _warm_boot=true so an already-running
## save resumes correctly on first rebuild without forcing a cold start.
var auto_start : bool = false
var _warm_boot : bool = false

# ── per-tick cache for performance ────────────────────────────────────────────
var _floor_piles_cache : Array = []
var _waste_containers_cache : Array = []
# Bales are scanned both in the feed loop (~line 1275) and the lazy fallback
# inside _bale_at(). Both paths previously called
# `get_tree().get_nodes_in_group("bale")` per tick — an O(N) scene-tree walk
# over potentially thousands of RigidBody3D yard bales. Cache once per tick to
# match the floor_pile / waste_container pattern above.
var _bales_cache : Array = []

# ── #52 advanced-systems wiring state ─────────────────────────────────────────
# The AirNetwork is a plant-wide autoload, so its compressors are registered ONCE
# (guarded by this flag) — rebuilding the line re-registers consumers in place
# (register_consumer updates a duplicate id) but must NOT stack more compressors.
var _air_compressors_registered : bool = false
# #99 — DRD pair registry. Keyed by pair_id (e.g. "dryer_pair") → {
#   "L": <node index>, "R": <node index>,
#   "cycle_L": MechDryerCycle, "cycle_R": MechDryerCycle,
#   "antiphase_done": bool,
# }
# When both L and R are present, the per-tick router (section 3 of tick()) sends
# 100% of the upstream share to whichever side is currently in BEFULLEN, and
# DRD2 (the R side) is started half a cycle ahead so the two drums never both
# accept at the same time.
var _dryer_pairs : Dictionary = {}
# #218 — set by rebuild() just before _discover() reruns; consumed by
# _build_dryer_pairs() so a surviving pair re-discovered after rebuild does
# NOT get its R-side antiphase jump re-applied (would slam state mid-shift).
var _dryer_pairs_prior_snapshot : Dictionary = {}
# #218 — set by rebuild() BEFORE _discover() runs; consumed by
# _attach_advanced_systems() so observer modules constructed for survivor
# slots reuse their prior ex/mfi/cc/mol/nir_ctrl/dryer_cycle refs instead
# of building fresh instances (which would re-parent the NirSorter under
# the scene tree, etc.). The key matches the same `id @ scene path`
# format the powered/spin rehydration uses. Empty between rebuilds.
var _restore_state : Dictionary = {}
# SCADA push throttle (~6 Hz) so we don't spam set_param every physics frame.
var _scada_push_accum : float = 0.0
const SCADA_PUSH_DT : float = 0.16
# The ScadaDashboard MainWorld instantiated (set via set_scada). Plain Node so this
# stays version-safe and no-ops when SCADA isn't present (headless / tests).
var _scada : Node = null

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
	# #218 — DO NOT reset cumulative telemetry counters here. Rebuild fires when
	# the operator adds a single HMI panel mid-shift, and the shift's running
	# totals (fed_mass, gran_mass, water_added, etc.) must survive that. Only
	# the explicit shift-reset button calls reset_shift_telemetry().
	# #218 — Snapshot SURVIVOR runtime state by (placeable_id @ scene path) so
	# any node that re-discovers after rebuild keeps its powered/spin/buffer/
	# in/out batches and its hand-mode HMI overrides. New nodes (no matching
	# key in old_state) start at the defaults their fresh dict was built with.
	var old_state : Dictionary = {}
	for nd in _nodes:
		# UNTYPED on purpose. `var node3d : Node = ...` THROWS "Trying to assign
		# invalid previously freed instance" when the dict still holds a machine
		# that was queue_free()d — the typed assignment fails BEFORE the
		# is_instance_valid() guard below can run, and the throw aborts rebuild(),
		# leaving _nodes pinned to the freed set for the rest of the session. Same
		# untyped-var-plus-guard idiom as _silo_feed_multiplier (:397-407).
		var node3d = nd.get("node", null)
		var key : String = ""
		if node3d != null and is_instance_valid(node3d):
			key = String(nd.get("id", "")) + "@" + String(node3d.get_path())
		else:
			key = String(nd.get("id", "")) + "#" + str(nd.get("index", _nodes.find(nd)))
		old_state[key] = {
			"powered":     nd.get("powered", false),
			"spin":        nd.get("spin", 0.0),
			"buffer":      nd.get("buffer", 0.0),
			"in":          nd.get("in", null),
			"out":         nd.get("out", null),
			"hand_mode":   nd.get("hand_mode", false),
			"manual_on":   nd.get("manual_on", false),
			"rpm_pct":     nd.get("rpm_pct", 1.0),
			# #218 — preserve observer modules so _attach_advanced_systems()
			# guards see existing instances and don't reconstruct them.
			"ex":          nd.get("ex", null),
			"mfi":         nd.get("mfi", null),
			"mol":         nd.get("mol", null),
			"cc":          nd.get("cc", null),
			"nir_ctrl":    nd.get("nir_ctrl", null),
			"dryer_cycle": nd.get("dryer_cycle", null),
		}
	# #99 — preserve the prior pair registry across the rebuild so freshly-
	# rediscovered pairs are detected (not yet present here) but the L/R
	# antiphase jump is NOT re-triggered on survivors.
	var prior_pairs : Dictionary = _dryer_pairs.duplicate()
	_dryer_pairs.clear()
	# #218 — Publish the snapshot + prior_pairs to MEMBER vars BEFORE
	# _discover() runs. _attach_advanced_systems() (called from inside
	# _discover) reads _restore_state and skips constructing observer
	# modules for slots where a survivor already exists — without this
	# the NirSorter add_child path runs on every rebuild and stacks
	# duplicate controller nodes under the sorter body.
	_restore_state = old_state
	_dryer_pairs_prior_snapshot = prior_pairs
	_discover()
	_link()
	# #218 — Rehydrate survivors BEFORE _init_plc() (which used to slam
	# powered=false / spin=0.0 unconditionally). Match by id @ scene path.
	for nd in _nodes:
		# UNTYPED on purpose. `var node3d : Node = ...` THROWS "Trying to assign
		# invalid previously freed instance" when the dict still holds a machine
		# that was queue_free()d — the typed assignment fails BEFORE the
		# is_instance_valid() guard below can run, and the throw aborts rebuild(),
		# leaving _nodes pinned to the freed set for the rest of the session. Same
		# untyped-var-plus-guard idiom as _silo_feed_multiplier (:397-407).
		var node3d = nd.get("node", null)
		var key : String = ""
		if node3d != null and is_instance_valid(node3d):
			key = String(nd.get("id", "")) + "@" + String(node3d.get_path())
		else:
			key = String(nd.get("id", "")) + "#" + str(nd.get("index", _nodes.find(nd)))
		if old_state.has(key):
			var s : Dictionary = old_state[key]
			nd["powered"]   = s["powered"]
			nd["spin"]      = s["spin"]
			nd["buffer"]    = s["buffer"]
			if s["in"] != null:   nd["in"]  = s["in"]
			if s["out"] != null:  nd["out"] = s["out"]
			nd["hand_mode"] = s["hand_mode"]
			nd["manual_on"] = s["manual_on"]
			nd["rpm_pct"]   = s["rpm_pct"]
			# #218 — survivor-PLC integration flag. The per-tick PLC
			# override (`_nodes[ni]["powered"] = _plc.is_powered(stage)`)
			# would otherwise immediately re-drop a survivor stage to
			# false while the staggered ramp catches up — observable as
			# every machine restart-flickering for ~20s after a rebuild.
			# When true, the per-tick override defers to the rehydrated
			# value; it's cleared once the PLC catches up to that stage.
			nd["_survivor_powered"] = bool(s["powered"])
			# #218 — re-attach surviving observer modules. Guards in
			# _attach_advanced_systems() then skip construction for these slots.
			if s["ex"]          != null: nd["ex"]          = s["ex"]
			if s["mfi"]         != null: nd["mfi"]         = s["mfi"]
			if s["mol"]         != null: nd["mol"]         = s["mol"]
			if s["cc"]          != null: nd["cc"]          = s["cc"]
			if s["nir_ctrl"]    != null and is_instance_valid(s["nir_ctrl"]):
				nd["nir_ctrl"] = s["nir_ctrl"]
			if s["dryer_cycle"] != null: nd["dryer_cycle"] = s["dryer_cycle"]
	_init_pipes()       # #145: turn each link into a transit delay-line
	_init_plc()         # #145: stage the downstream-first power-up;
						# _init_plc reads _survivor_powered to pre-power
						# survivor stages so they DON'T re-stagger.
	_spawn_connectors()
	_index_silo_sensors()    # #A3: build target-node → sensor lookup for surge wiring
	# Consume the snapshot — one-shot for this rebuild. Subsequent reads
	# (HMI placement scans, per-tick code) must see an empty dict.
	_restore_state = {}
	print("[LineFlow] %d machines, %d links (transport physicalized)" % [_nodes.size(), _edges.size()])

## #218 — Explicit shift telemetry reset. The shift-reset button on the
## supervisor HMI calls this; rebuild() must NOT touch these counters or a
## mid-shift HMI placement would zero the operator's running totals.
func reset_shift_telemetry() -> void:
	fed_mass = 0.0
	gran_mass = 0.0
	waste_mass = 0.0
	water_added = 0.0
	water_removed = 0.0
	contam_removed = 0.0
	poly_rejected = 0.0
	_gran_q_accum = 0.0

## Save-file loader must call this BEFORE the first rebuild() after a
## resume so the line picks up where it left off rather than cold-starting.
## auto_start stays false — only _warm_boot fires once.
func mark_warm_boot() -> void:
	_warm_boot = true

# ── #A3 silo-level-sensor surge wiring ───────────────────────────────────────
## Build a {silo_node3d → SiloLevelSensor} lookup so the per-edge delivery loop
## can grab the right sensor in O(1). Sensors register via the
## "silo_level_sensor" group and expose target_silo() to resolve their NodePath.
## Sensors whose silo_path can't resolve yet (silo spawned later) just skip;
## _silo_sensor_for_node() retries lazily on demand.
func _index_silo_sensors() -> void:
	_silo_sensor_by_node.clear()
	var tree := get_tree()
	if tree == null:
		return
	for s in tree.get_nodes_in_group("silo_level_sensor"):
		if s == null or not is_instance_valid(s):
			continue
		var silo : Node3D = null
		if s.has_method("target_silo"):
			silo = s.call("target_silo")
		if silo != null and is_instance_valid(silo):
			_silo_sensor_by_node[silo] = s

## Look up the sensor governing a given target node. Falls back to a one-shot
## group scan if the cache misses — handles the case where a sensor's silo_path
## resolved AFTER rebuild() ran (e.g. silo macro spawned its sensor child late).
## Returns null when this silo has no sensor; the caller treats that as
## multiplier = 1.0 (passthrough).
func _silo_sensor_for_node(n) -> Node:
	if n == null or not is_instance_valid(n):
		return null
	if _silo_sensor_by_node.has(n):
		var s = _silo_sensor_by_node[n]
		if s != null and is_instance_valid(s):
			return s
		_silo_sensor_by_node.erase(n)
	# Cache miss — try once more by walking the group. Cheap (sensor count
	# tops out at one per silo, ~half a dozen for a fully-built plant).
	var tree := get_tree()
	if tree == null:
		return null
	for s2 in tree.get_nodes_in_group("silo_level_sensor"):
		if s2 == null or not is_instance_valid(s2) or not s2.has_method("target_silo"):
			continue
		var tgt : Node3D = s2.call("target_silo")
		if tgt == n:
			_silo_sensor_by_node[n] = s2
			return s2
	return null

## #A3 — per-tick feed multiplier for an edge whose downstream is `dst_node`.
## Bridging the level sensor (operator anecdote: "the wire was the governor;
## we took it out") removes the soft throttle: this multiplier becomes 1.5,
## upstream over-takes from its out-batch and the silo surges. Below
## HIGH_LEVEL_PCT this is just 1.0 (normal cruise). Above HIGH_LEVEL_PCT
## without bridging it drops to 0.0 — the parcel parks at the source and
## material backs up there (conserving), exactly like the PLC closing the
## metering damper. Returns 1.0 (no-op) when the destination has no sensor.
func _silo_feed_multiplier(dst_node) -> float:
	# Guard: `_nodes` can hold a machine dict whose "node" was FREED since it was
	# recorded (a placeable removed mid-run). A freed Object fails the typed-param
	# check AND the downstream sensor lookup, spamming "previously freed is not a
	# subclass" from the core tick. Untyped param + validity guard → no governor.
	if dst_node == null or not is_instance_valid(dst_node):
		return 1.0
	var sensor := _silo_sensor_for_node(dst_node)
	if sensor == null or not sensor.has_method("effective_feed_multiplier"):
		return 1.0
	return float(sensor.call("effective_feed_multiplier"))

## Mass-weighted average quality (0..100) of all granulaat produced this run.
func granulaat_quality() -> float:
	return _gran_q_accum / gran_mass if gran_mass > 0.0 else 0.0

## Input port world position for `node3d`. Variable belts override the standard
## bounding-box fraction with their persisted vb_start endpoint — without this,
## the fractional `inf` would land in the wrong place for a span that's longer
## than its catalog bounding-box size.
func _node_win(node3d: Node3D, id: String, inf: Vector3, size: Vector3) -> Vector3:
	if id == "variable_belt" and node3d.has_meta("vb_start"):
		return node3d.get_meta("vb_start")
	return node3d.to_global(Vector3(inf.x * size.x, inf.y * size.y, inf.z * size.z))

func _node_wout(node3d: Node3D, id: String, outf: Vector3, size: Vector3) -> Vector3:
	if id == "variable_belt" and node3d.has_meta("vb_end"):
		return node3d.get_meta("vb_end")
	return node3d.to_global(Vector3(outf.x * size.x, outf.y * size.y, outf.z * size.z))

## #54 — splitter's second output port. Returns the wout's value when the
## profile has no "out2" key (so non-splitters carry a copy of their main output
## and the linker can safely read this without a null check; the splitter code
## path is the only one that actually consumes wout2 separately).
func _node_wout2(node3d: Node3D, prof: Dictionary, size: Vector3) -> Vector3:
	if not prof.has("out2"):
		return Vector3.ZERO
	var o2 : Vector3 = prof["out2"]
	return node3d.to_global(Vector3(o2.x * size.x, o2.y * size.y, o2.z * size.z))

func _discover() -> void:
	_nodes.clear()
	_code_conflicts.clear()
	# Per-instance addressing state (see the _code_conflicts declaration).
	# id -> instances seen so far; l3c_code -> the scene path that claimed it.
	var id_ordinal : Dictionary = {}
	var code_owner : Dictionary = {}
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
		# PLANT ADDRESS. An explicit meta wins (a bench may hand-stamp one, e.g.
		# tests/FlakeCouplingTest.gd:64), otherwise the code is DERIVED from the
		# macro membership BuildMode already stamps and already round-trips through
		# the save file — so no new persisted key exists and every legacy save loads
		# unchanged. Only the line_3c macro resolves (Line3CDef.code_for_macro_entry).
		var l3c_code   : String = String(node3d.get_meta("l3c_code")) if node3d.has_meta("l3c_code") else ""
		if l3c_code == "" and node3d.has_meta("macro_id") and node3d.has_meta("macro_index"):
			l3c_code = Line3CDefScript.code_for_macro_entry(
				String(node3d.get_meta("macro_id")), int(node3d.get_meta("macro_index")))
		# UNIQUENESS IS A PRECONDITION, not a nicety: _link()'s code_idx is a
		# first-match map on this code, so a second claimant would silently steal
		# the first one's downstream edges AND its calibrated current. Refuse it
		# and record the refusal instead — the ledger is asserted empty by the tests.
		if l3c_code != "":
			if code_owner.has(l3c_code):
				_code_conflicts.append({
					"code": l3c_code,
					"kept": String(code_owner[l3c_code]),
					"refused": String(node3d.get_path()),
				})
				push_error("[LineFlow] l3c_code '%s' already claimed by %s — refusing %s (it falls back to an ordinal key)"
					% [l3c_code, String(code_owner[l3c_code]), String(node3d.get_path())])
				l3c_code = ""
			else:
				code_owner[l3c_code] = String(node3d.get_path())
		# The per-instance HANDLE every front-end addresses this machine by.
		var ordinal : int = int(id_ordinal.get(id, 0)) + 1
		id_ordinal[id] = ordinal
		var node_key : String = l3c_code if l3c_code != "" else "%s#%d" % [id, ordinal]
		# #99 — paired-stage tags. Empty for everything except L3C.14L/R (the
		# mech-dryer pair). The router uses these to fan 100% of incoming material
		# to the drum currently in BEFULLEN instead of splitting it evenly.
		var pair_id   : String = Line3CDefScript.pair_id_for(l3c_code) if l3c_code != "" else ""
		var pair_side : String = Line3CDefScript.pair_side_for(l3c_code) if l3c_code != "" else ""
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
			# `id` stays the plain MODEL selector — MachineFlow.profile,
			# PlaceableCatalog.get_item, the _is_extruder/_is_high_load_motor
			# substring dispatchers and CrewManager's zone token-matching all key
			# on it, so it must never be suffixed. `key` is the sibling ADDRESS.
			"key":   node_key,
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
			# #99 — paired-stage routing tags (mech-dryer L/R only).
			"pair_id":       pair_id,
			"pair_side":     pair_side,
			# Populated in _attach_advanced_systems() with a MechDryerCycle for
			# nodes whose pair_id == "dryer_pair". Null on everything else.
			"dryer_cycle":   null,
			"amps_nominal":  amps_nom,
			"amps":          0.0,
			"win":   _node_win(node3d, id, inf, size),
			"wout":  _node_wout(node3d, id, outf, size),
			# #54 splitters carry a second output port — used by the linker to add
			# a SECOND outgoing edge so the switch belt can route to both VSS and
			# U-bay. Null world position when the profile didn't define one.
			"wout2": _node_wout2(node3d, prof, size),
			"in":    MaterialBatch.new(),
			"out":   MaterialBatch.new(),
			# Live telemetry, refreshed each tick so the HMI can read real operator
			# numbers per machine (smoothed throughput; instantaneous stream state).
			"thru":    0.0,    # kg/s leaving this machine (EMA-smoothed)
			"moist":   0.0,    # % moisture of the stream leaving
			"contam":  0.0,    # % contamination of the stream leaving
			"quality": 0.0,    # 0..100 melt-quality grade of the stream leaving
			"buffer":  0.0,    # kg waiting in this machine's input buffer
			# #145 transport: the machine's conveying rotor(s), its live spin-up
			# state (0..1), and whether the PLC has powered it. `mechs` is the
			# FULL list (doseersilo: 3 augers, frictiewasser: 2 stirrers);
			# `mech` keeps the legacy primary-rotor pointer for HUD widgets
			# that show a single RPM. The set_running cascade walks `mechs`
			# so EVERY rotor responds to power-state changes, not just the
			# first one listed.
			"mechs":   _find_mechanisms(node3d),
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
			# Flow-gated visuals: steam plume + extruder die-face melt strands only
			# show while material is actually being processed (no invention from nothing).
			"plume":       _find_steam_plume(node3d),
			"die_switcher": _find_die_switcher(node3d),
			# ── #52 advanced-system observers (null unless this node qualifies) ───
			# ex/mfi: extruder thermal+rheology model + its MFI soft-sensor (extruders).
			# mol: motor-overload trip model (high-load mills/shredders/friction sep).
			# air_id: the AirNetwork consumer key for air-driven machines (sorter/PCU).
			# _backlog_kg/_moved_kg: per-tick load bookkeeping for the motor model
			#   (pure OBSERVATIONS of the existing split — they change no flow math).
			"ex":          null,
			"mfi":         null,
			"mol":         null,
			"air_id":      "",
			"die_pressure": 0.0,
			"melt_temp":    0.0,
			"viscosity":    0.0,
			"mfi_value":    0.0,
			"_backlog_kg":  0.0,
			"_moved_kg":    0.0,
			# #137 — switch_belt jog controller. Populated below for switch_belt
			# placeables only; everyone else carries null and the tick path skips
			# the jog logic entirely.
			"switch_ctrl":  null,
			# #138 — conveyor-8 bidirectional controller. Populated below for
			# transportband_8 only.
			"c8_ctrl":      null,
		})
		# #137 — attach the jog controller to switch_belt bodies and stash it on
		# the node dict so the tick can read jog_x without a per-frame find_child.
		if id == "switch_belt":
			_nodes[_nodes.size() - 1]["switch_ctrl"] = SwitchBeltScript.attach_to(node3d)
		# #138 — attach the bidirectional ramp controller to C8.
		elif id == "transportband_8":
			_nodes[_nodes.size() - 1]["c8_ctrl"] = Conveyor8Script.attach_to(node3d)
	# Attach the advanced-system observers now that every node dict exists.
	_attach_advanced_systems()

# ── #52 advanced-system observers (attach + classify) ─────────────────────────
## Set the ScadaDashboard MainWorld owns so tick() can push live state + params.
## Plain Node + has_method guards keep this safe when SCADA is absent.
func set_scada(scada: Node) -> void:
	_scada = scada

## True for any node whose id begins with "extruder" (extruder_1/3a/3b/3c/6/screw).
static func _is_extruder(id: String) -> bool:
	return id.begins_with("extruder")

## True for the high mechanical-load process drives the motor-overload model covers:
## the Maalmolen (mill), the shredders, and the friction separators/washers. Matched
## by id substring OR the "shred" process tag so build-placed variants are caught too.
static func _is_high_load_motor(id: String, process: String) -> bool:
	var lid := id.to_lower()
	if lid.find("mill") >= 0 or lid.find("shredder") >= 0 \
			or lid.find("friction") >= 0:
		return true
	return process == "shred"

## #52 — true for nodes that host a CutterCompactor thermo model: the explicit
## "compactor" / "cutter_compactor" ids and anything tagged process="compact".
static func _is_cutter_compactor(id: String, process: String) -> bool:
	var lid := id.to_lower()
	if lid == "cutter_compactor" or lid == "compactor":
		return true
	return process == "compact"

## True for any node modelled as a TITECH / TOMRA NIR optical sorter. Matched by
## id (titech_sort / tomra_sort) OR the "optical" process tag so the shaft-wrap
## controller attaches to any future NIR variant that adopts the same flow tag.
static func _is_nir_sorter(id: String, process: String) -> bool:
	var lid := id.to_lower()
	if lid == "titech_sort" or lid == "tomra_sort":
		return true
	if lid.find("nir") >= 0 or lid.find("titech") >= 0 or lid.find("tomra") >= 0:
		return true
	return process == "optical"

## The AirNetwork consumer id for an air-driven machine, or "" if it taps no air.
## The TITECH/TOMRA NIR sorter's ejector bank and the compactor/PCU pneumatic ram
## are the real header consumers; matched by id substring or process tag.
static func _air_consumer_id(id: String, process: String) -> String:
	var lid := id.to_lower()
	if lid.find("titech") >= 0 or lid.find("tomra") >= 0 or lid.find("nir") >= 0 \
			or process == "optical":
		return "titech_sort"
	if lid.find("compactor") >= 0 or lid.find("pcu") >= 0 or process == "compact":
		return "pcu_compactor"
	return ""

## Compose the per-node observer modules (run ALONGSIDE the flow — see header). Each
## attachment is guarded so an absent system simply leaves the slot null and every
## tick hook below no-ops for that node. Also registers the line's air consumers.
func _attach_advanced_systems() -> void:
	for nd in _nodes:
		var id : String = String(nd["id"])
		var proc : String = String(nd["process"])
		# #218 — observer construction is guarded by an existing-instance check so
		# survivors keep their internal state (extruder thermal accumulator,
		# motor-overload trip integrator, NIR wrap mass) across a rebuild. Only
		# newly-discovered nodes (whose dict was just freshly constructed in
		# _discover and so still has null observer slots) get fresh modules.
		# We FIRST look the survivor refs up in _restore_state (published by
		# rebuild() before _discover ran) so observers that add_child()
		# themselves to the scene tree (NirSorter) are NEVER reconstructed
		# for a survivor — without this, the controller node would be
		# silently re-parented every rebuild and the scene tree leaks.
		var rk : String = ""
		var n3d : Node = nd.get("node", null)
		if n3d != null and is_instance_valid(n3d):
			rk = String(nd.get("id", "")) + "@" + String(n3d.get_path())
		var prior : Dictionary = _restore_state.get(rk, {}) if rk != "" else {}
		# 1) Extruder thermal/rheology model + 2) its MFI soft-sensor.
		if _is_extruder(id):
			if nd.get("ex", null) == null:
				var prior_ex = prior.get("ex", null) if not prior.is_empty() else null
				nd["ex"] = prior_ex if prior_ex != null else ExtruderScrewScript.new()
			if nd.get("mfi", null) == null:
				var prior_mfi = prior.get("mfi", null) if not prior.is_empty() else null
				nd["mfi"] = prior_mfi if prior_mfi != null else MfiProxyScript.new()
		# #52 — Cutter-compactor thermo + Donut-stall model. One per compactor node;
		# driven by rpm_pct and live throughput, publishes pot_temp + band to SCADA.
		if _is_cutter_compactor(id, proc):
			if nd.get("cc", null) == null:
				var prior_cc = prior.get("cc", null) if not prior.is_empty() else null
				nd["cc"] = prior_cc if prior_cc != null else CutterCompactorScript.new(id)
		# 3) Motor-overload (current-trip) model on the high-load process drives. Seed
		#    its nominal current from the calibrated HMI amps when we have them, so a
		#    metered Line 3C drive trips against realistic numbers.
		if _is_high_load_motor(id, proc):
			if nd.get("mol", null) == null:
				var prior_mol = prior.get("mol", null) if not prior.is_empty() else null
				if prior_mol != null:
					nd["mol"] = prior_mol
				else:
					var nom : float = float(nd.get("amps_nominal", 0.0))
					if nom <= 0.0:
						nom = 90.0   # MotorOverload's own default full-load current
					# Trip threshold sits a touch above nominal; locked-rotor ~5× nominal.
					var mol = MotorOverloadScript.new(id, nom, nom * 5.0, maxf(nom * 1.5, 120.0), 3.0)
					nd["mol"] = mol
		# 4) Air consumer registration (one global header; consumers re-register in
		#    place on rebuild, so this is safe to call every rebuild).
		var air_id : String = _air_consumer_id(id, proc)
		if air_id != "":
			nd["air_id"] = air_id
		# 5) NIR shaft-wrap controller (TITECH/TOMRA). Owns a fibrous-wrap
		#    accumulator that grows with moved throughput, slows eff_rate above
		#    TRIP_WRAP_G (350 g), and stamps a back-reference on the placed
		#    Node3D so the wire-cutter interaction (TitechShaftCut) can resolve
		#    us from a crosshair hit without scanning the whole tree. Parented
		#    under the body so its lifetime tracks the placeable; freeing the
		#    sorter (delete / rebuild) frees the controller too.
		if _is_nir_sorter(id, proc):
			var existing_ctrl = nd.get("nir_ctrl", null)
			# Reuse the survivor's NirSorter controller BEFORE checking
			# the freshly-constructed dict's slot — this controller is a
			# Node parented under the sorter body via add_child(), so a
			# new instance every rebuild leaks add_child calls into the
			# scene tree (the survey flagged this explicitly).
			var prior_nir = prior.get("nir_ctrl", null) if not prior.is_empty() else null
			if (existing_ctrl == null or not is_instance_valid(existing_ctrl)) \
					and prior_nir != null and is_instance_valid(prior_nir):
				nd["nir_ctrl"] = prior_nir
				existing_ctrl = prior_nir
			if existing_ctrl == null or not is_instance_valid(existing_ctrl):
				var nir_node : Node3D = nd["node"] as Node3D
				if nir_node != null and is_instance_valid(nir_node):
					var ctrl : NirSorterScript = NirSorterScript.new()
					ctrl.name = "NirSorterCtrl"
					nir_node.add_child(ctrl)
					ctrl.bind(nir_node, id)
					nd["nir_ctrl"] = ctrl
	_register_air_network()
	# 5) #99 — DRD pair build. Each mech_dryer node with a pair_id gets its own
	#    MechDryerCycle (state machine over IDLE/BEFULLEN/TROCKNEN/ENTLEEREN); the
	#    pair registry stores the L/R node indices + cycle refs so tick() can route
	#    100% of incoming flake to whichever side is currently in BEFULLEN. The R
	#    side is started half a cycle ahead so the two drums never both accept at
	#    once (antiphase requirement).
	_build_dryer_pairs()

## Register the compressors ONCE and the line's air consumers (re-registering an
## existing consumer id just updates it, so a rebuild never stacks duplicates). This
## is what "turns on" the air header in-game (it won't pressurise until a compressor
## exists), pairing with the menu-alarm fix (#77).
func _register_air_network() -> void:
	var air := _air_network()
	if air == null:
		return
	# Collect the distinct air consumers present on the line FIRST. A plant with no
	# air-using machine has nothing to pressurise — so it has NO running compressors
	# and NO header pressure. We therefore skip the compressor bank entirely when
	# there are zero consumers. This is why an empty new world has a dead air ring
	# (no phantom 24 Nm³/min from nowhere) and never sounds a NO-AIR alarm.
	var air_ids : Dictionary = {}
	for nd in _nodes:
		var aid : String = String(nd.get("air_id", ""))
		if aid != "":
			air_ids[aid] = true

	# Compressors: only spin up the bank once there is at least one consumer, and
	# only on the first build (guard so a rebuild never stacks duplicates).
	if not air_ids.is_empty() and not _air_compressors_registered and air.has_method("register_compressor"):
		# Two screw compressors charging the single ring main. Sized so the header
		# holds nominal against the registered consumers' full draw with headroom.
		air.call("register_compressor", 12.0, true)
		air.call("register_compressor", 12.0, true)
		_air_compressors_registered = true

	# Consumers: register one per distinct air id present on the line.
	if air.has_method("register_consumer"):
		for aid in air_ids:
			# Full-tilt demand (Nm³/min): the TITECH ejector bank is the thirsty one,
			# the PCU ram a lighter intermittent draw.
			var demand : float = 8.0 if aid == "titech_sort" else 4.0
			air.call("register_consumer", aid, demand)

	# Visible compressor pair — additive to the abstract air bank above. We spawn
	# two physical placeables (compressor_a + compressor_b) so the operator can
	# actually SEE the kit pressurising the header. Guarded by node-name lookups
	# so a rebuild never stacks duplicates; only the first rebuild that finds at
	# least one consumer actually spawns them (matches the air_bank guard).
	if not air_ids.is_empty():
		_spawn_visible_compressors()

## Spawn the two visible compressor placeables next to the player_spawn (or at
## the optional WorldLayout.compressor_spawn marker when the operator has placed
## one). Idempotent: re-running it on every rebuild is safe because each spawn
## is gated by a fixed node name lookup under the world root. The placeables are
## additive — they don't enter LineFlow's material graph (Hoses & Air rows are
## visual only) and don't change the abstract AirNetwork bank registered above.
func _spawn_visible_compressors() -> void:
	# World root is whoever owns this LineFlow (typically MainWorld). We attach
	# directly under it so the placeables sit alongside the rest of the placed
	# scene, are saved/loaded with the world, and survive a LineFlow rebuild.
	var world : Node = get_parent()
	if world == null:
		return
	# Marker → scene-space. WorldLayout.compressor_spawn == Vector3.ZERO means
	# "no marker", so fall back to a default offset from player_spawn. Both go
	# through _layout_marker_to_scene so the frame is decided in one place.
	# player_spawn is itself scene-absolute, so the fallback below is a plain
	# scene position and the conversion leaves it alone — it used to be rotated
	# and re-anchored, double-counting the anchor it was already built from.
	var layout := get_node_or_null("/root/WorldLayout")
	var marker : Vector3 = Vector3.ZERO
	if layout != null and "compressor_spawn" in layout:
		marker = layout.get("compressor_spawn")
	if marker == Vector3.ZERO:
		# Default: 20m east, 20m north of the player spawn — clear of the plant
		# core but close enough to walk to. Y stays at floor level.
		var player_anchor : Vector3 = Vector3.ZERO
		if layout != null and "player_spawn" in layout:
			player_anchor = layout.get("player_spawn")
		marker = player_anchor + Vector3(20.0, 0.0, 20.0)
	var base_pos : Vector3 = _layout_marker_to_scene(marker)
	# Spawn A on the marker, B 2m to the right (+X in scene space). Each is
	# guarded by its node name so a rebuild reuses the existing instance.
	_spawn_one_compressor(world, "compressor_a", "compressor_a_visible", base_pos)
	_spawn_one_compressor(world, "compressor_b", "compressor_b_visible", base_pos + Vector3(2.0, 0.0, 0.0))

func _spawn_one_compressor(world: Node, catalog_id: String, node_name: String, scene_pos: Vector3) -> void:
	# Idempotent guard — a prior rebuild already placed this one.
	if world.get_node_or_null(node_name) != null:
		return
	var n : Node3D = PlaceableCatalog.build_node(catalog_id, false, false)
	if n == null:
		push_warning("[LineFlow] Could not build %s for visible compressor spawn" % catalog_id)
		return
	n.name = node_name
	world.add_child(n)
	n.global_transform = Transform3D(Basis.IDENTITY, scene_pos)

## The plant-wide compressed-air autoload, or null when it isn't registered
## (headless test / unit run). Reached via the tree root (LineFlow is a Node).
func _air_network() -> Node:
	return get_node_or_null("/root/AirNetwork")

## The header's 0..1 capability factor (1.0 = full pressure, nothing slowed). 1.0
## when AirNetwork is absent or lacks the query — air gating then never bites.
func _air_factor() -> float:
	var air := _air_network()
	if air != null and air.has_method("consumer_air_factor"):
		return float(air.call("consumer_air_factor"))
	return 1.0

# ── #99 DRD BATCH-DRYER PAIR ─────────────────────────────────────────────────
## Walk every node and group those tagged with a pair_id into a {pair_id → {
##   "L": idx, "R": idx, "cycle_L": MechDryerCycle, "cycle_R": MechDryerCycle,
##   "antiphase_done": bool}}. Each mech_dryer node also gets its own
## MechDryerCycle stashed on its node dict (nd["dryer_cycle"]) — so even a SINGLE
## drum (only L placed, no pair partner) still cycles BEFULLEN/TROCKNEN locally.
## Only when BOTH sides exist is the pair recorded as routable, and only then
## is the R side jumped half a cycle ahead so the two never accept at once.
func _build_dryer_pairs() -> void:
	# Per-node cycle assignment first. Each mech_dryer in the topology gets one.
	# Survivor reuse: pull from _restore_state when this node had a cycle
	# attached before rebuild — preserves accumulated heater/fill state
	# instead of slamming the drum back to IDLE on every HMI placement.
	for i in _nodes.size():
		var nd : Dictionary = _nodes[i]
		if String(nd.get("pair_id", "")) == "":
			continue
		if nd.get("dryer_cycle") == null:
			var rk : String = ""
			var n3d : Node = nd.get("node", null)
			if n3d != null and is_instance_valid(n3d):
				rk = String(nd.get("id", "")) + "@" + String(n3d.get_path())
			var prior_cycle = null
			if rk != "" and _restore_state.has(rk):
				prior_cycle = (_restore_state[rk] as Dictionary).get("dryer_cycle", null)
			if prior_cycle != null:
				nd["dryer_cycle"] = prior_cycle
			else:
				nd["dryer_cycle"] = MechDryerCycleScript.new(MechDryerModelScript.new())
	# Now build pair records ({pair_id → {L,R,cycle_L,cycle_R,antiphase_done}}).
	var pairs : Dictionary = {}
	for i in _nodes.size():
		var nd : Dictionary = _nodes[i]
		var pid : String = String(nd.get("pair_id", ""))
		if pid == "":
			continue
		var side : String = String(nd.get("pair_side", ""))
		if side != "L" and side != "R":
			continue
		var rec : Dictionary = pairs.get(pid, {
			"L": -1, "R": -1, "cycle_L": null, "cycle_R": null,
			"antiphase_done": false,
		})
		rec[side] = i
		rec["cycle_" + side] = nd.get("dryer_cycle")
		pairs[pid] = rec
	# First-start antiphase: the R side jumps half a cycle ahead so DRD2 begins
	# in TROCKNEN already half-soaked. #218 — only fire for FRESHLY-DISCOVERED
	# pairs (no entry in the prior snapshot). Surviving pairs carry their L/R
	# antiphase forward in their preserved MechDryerCycle state.
	for pid in pairs.keys():
		var r : Dictionary = pairs[pid]
		var pair_complete : bool = int(r["L"]) >= 0 and int(r["R"]) >= 0
		var was_known_before : bool = _dryer_pairs_prior_snapshot.has(pid)
		if was_known_before:
			# Survivor — inherit the prior antiphase flag so a re-rebuild
			# doesn't slam R back into the half-cycle jump.
			var prior : Dictionary = _dryer_pairs_prior_snapshot[pid]
			r["antiphase_done"] = bool(prior.get("antiphase_done", false))
		if pair_complete and not bool(r["antiphase_done"]) and not was_known_before:
			var c_r = r["cycle_R"]
			if c_r != null and c_r.has_method("force_antiphase_start"):
				c_r.call("force_antiphase_start")
			r["antiphase_done"] = true
		pairs[pid] = r
	_dryer_pairs = pairs
	# Consume the prior snapshot — it was a one-shot guard for this rebuild.
	_dryer_pairs_prior_snapshot = {}

## #99 — tick the L/R MechDryerCycle for every registered pair. The cycle
## state machine swings IDLE → BEFULLEN → TROCKNEN → ENTLEEREN; its dryer model
## just integrates fill_pct vs heater_on, so we drive its in/out flows from the
## per-tick throughput of its node (already tracked in nd["thru"]). Skip rigs
## that don't have a cycle attached (single-drum builds with no pair partner).
func _tick_dryer_pairs(delta: float) -> void:
	# First tick every per-node cycle (even unpaired drums get heat/level state).
	for nd in _nodes:
		var cyc = nd.get("dryer_cycle")
		if cyc == null:
			continue
		# Drive the underlying drum model: inflow = the upstream branch's share
		# that landed in this node's input buffer this tick; outflow = the
		# throughput leaving (nd["thru"] kg/s). We approximate inflow from
		# moved_kg + backlog change, but a defensive minimum just uses thru, so
		# the drum cycles even when the bookkeeping is sparse.
		var inflow : float = maxf(0.0, float(nd.get("_moved_kg", 0.0))) / maxf(delta, 0.0001)
		var outflow : float = float(nd.get("thru", 0.0))
		if cyc.dryer != null:
			cyc.dryer.tick(delta, inflow, outflow)
		cyc.tick(delta)

		# Drive the visual gates if they exist
		var n3d : Node3D = nd.get("node", null) as Node3D
		if n3d != null and is_instance_valid(n3d):
			var bg = n3d.get_node_or_null("besch_gate")
			if bg != null:
				bg.visible = bool(cyc.besch_open)
			var eg = n3d.get_node_or_null("entleer_gate")
			if eg != null:
				eg.visible = bool(cyc.entleer_open)

## #99 — which side of a pair is currently in BEFULLEN (accepting flake).
## Returns "L", "R", or "" when neither side is BEFULLEN (both drying / idle).
## Falls back to whichever side has the LOWEST fill_pct so material is never
## stranded when both happen to be in TROCKNEN at the same instant.
func _dryer_pair_accept_side(rec: Dictionary) -> String:
	var c_l = rec.get("cycle_L")
	var c_r = rec.get("cycle_R")
	var BEFULLEN := MechDryerCycle.Step.BEFULLEN
	var l_befullen : bool = c_l != null and int(c_l.step) == BEFULLEN
	var r_befullen : bool = c_r != null and int(c_r.step) == BEFULLEN
	if l_befullen and not r_befullen:
		return "L"
	if r_befullen and not l_befullen:
		return "R"
	if l_befullen and r_befullen:
		# Both somehow BEFULLEN — pick the emptier drum.
		var lf : float = c_l.dryer.fill_pct if c_l.dryer != null else 100.0
		var rf : float = c_r.dryer.fill_pct if c_r.dryer != null else 100.0
		return "L" if lf <= rf else "R"
	# Neither BEFULLEN — route to the emptier drum so it can transition to
	# BEFULLEN on its own (the IDLE → BEFULLEN guard is fill_pct < 89%).
	var lf2 : float = c_l.dryer.fill_pct if c_l != null and c_l.dryer != null else 100.0
	var rf2 : float = c_r.dryer.fill_pct if c_r != null and c_r.dryer != null else 100.0
	return "L" if lf2 <= rf2 else "R"

## #99 — given the list of edge-indices emerging from source `src_idx` and the
## per-branch shares array (in the same order), bias 100% of the share to the
## paired drum that's currently in BEFULLEN. Returns the (possibly-overwritten)
## shares array. Untouched when:
##   * the source doesn't feed exactly two paired siblings, or
##   * the two siblings don't belong to the same pair, or
##   * the pair isn't registered in _dryer_pairs.
func _maybe_apply_dryer_pair_routing(src_edges: Array, shares: Array) -> Array:
	if src_edges.size() != 2 or shares.size() != 2:
		return shares
	var b0 : Dictionary = _nodes[int(_edges[int(src_edges[0])]["b"])]
	var b1 : Dictionary = _nodes[int(_edges[int(src_edges[1])]["b"])]
	var pid0 : String = String(b0.get("pair_id", ""))
	var pid1 : String = String(b1.get("pair_id", ""))
	if pid0 == "" or pid0 != pid1:
		return shares
	if not _dryer_pairs.has(pid0):
		return shares
	var rec : Dictionary = _dryer_pairs[pid0]
	var accept : String = _dryer_pair_accept_side(rec)
	if accept == "":
		return shares
	var side0 : String = String(b0.get("pair_side", ""))
	# 100% to whichever edge points at the accepting drum.
	var to_b0 : bool = (side0 == accept)
	return [1.0 if to_b0 else 0.0, 0.0 if to_b0 else 1.0]

func _link() -> void:
	_edges.clear()
	var n := _nodes.size()
	# Map Line 3C HMI codes → node index, so the explicit branch topology (#1) can
	# resolve its [from,to] edges. Lets one stage feed TWO downstream (a split) and
	# two stages feed ONE (a merge) — impossible with the old single-nearest linker.
	# This is a FIRST-MATCH map; it is safe only because _discover() refuses a
	# duplicate l3c_code outright (see _code_conflicts) so no code reaches here twice.
	var code_idx : Dictionary = {}
	for i in n:
		var c : String = String(_nodes[i].get("l3c_code", ""))
		if c != "":
			code_idx[c] = i
	# Node3D path → node index, so we can resolve the macro-builder's lf_explicit_outs
	# meta (each entry references a downstream by its scene path). (#71)
	var path_idx : Dictionary = {}
	for i in n:
		var n3d : Node3D = _nodes[i]["node"] as Node3D
		if n3d != null:
			path_idx[n3d.get_path()] = i
	# #71 — MACRO BRANCH METADATA pass. A node placed by `_build_full_line`
	# carries an `lf_explicit_outs` array of {path, recirc} dicts identifying
	# its explicit downstream targets (split or recirc back-edge). These bypass
	# the geometry fallback so the 3A dry loop closes and the 3B L-R split fans
	# out to both dryers, regardless of placement spacing. Tagged sources are
	# NOT considered by the geometry pass below — their downstreams are fully
	# specified here.
	var explicit_src : Dictionary = {}    # idx → true when this node's downstream is fully tagged
	for i in n:
		var n3d_i : Node3D = _nodes[i]["node"] as Node3D
		if n3d_i == null or not n3d_i.has_meta("lf_explicit_outs"):
			continue
		var outs : Array = n3d_i.get_meta("lf_explicit_outs")
		if not (outs is Array) or outs.is_empty():
			continue
		explicit_src[i] = true
		for entry in outs:
			if not (entry is Dictionary):
				continue
			var tpath = entry.get("path", null)
			if tpath == null or not path_idx.has(tpath):
				continue
			var j : int = int(path_idx[tpath])
			if j == i or _edge_exists(i, j):
				continue
			_edges.append({"a": i, "b": j, "recirc": bool(entry.get("recirc", false))})
	for i in n:
		var a: Dictionary = _nodes[i]
		if String(a["role"]) == "sink":
			continue                       # sinks consume, never feed downstream
		# #71 — node was tagged with `lf_explicit_outs` by the macro builder:
		# its downstreams are fully specified above. Skip geometry fallback to
		# avoid adding a SPURIOUS third edge alongside an L-R split or recirc.
		if explicit_src.has(i):
			continue
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
		# 2) GEOMETRY fallback (build-mode objects / other lines).
		#
		# #78 fix: the original single-nearest picker would pick a WRONG-direction
		# target (e.g. a silo's bottom output near a cyclone's high input) and the
		# only safeguard — a 2-cycle check — fired too late to undo it. Result was
		# silo→cyclone "back-links" that left the cyclone with no outgoing edge, so
		# the line never reached the extruder.
		#
		# New approach: sort ALL in-range inputs by distance, then walk them in
		# order and accept the first one that passes two filters:
		#   (a) semantic process-direction (buffer cannot feed airsep, etc.) — a
		#       small allow/deny table on the (a.process, b.process) pair
		#   (b) full DAG cycle prevention via DFS reachability — picking this edge
		#       must not create a cycle of any length, not just length 2
		var a_proc : String = String(a.get("process", ""))
		var b1 := _link_best_target(i, a["wout"], a_proc)
		if b1 >= 0:
			_edges.append({"a": i, "b": b1})
		# #54 — role="splitter" (e.g. switch_belt) emits a SECOND outgoing edge
		# from its alternate output port. Same filters (cycle / direction / range)
		# apply. Excludes b1 so the splitter can't point both outputs at the same
		# downstream — that would defeat the point of having two routes.
		if String(a["role"]) == "splitter":
			var b2 := _link_best_target(i, a["wout2"], a_proc, b1)
			if b2 >= 0:
				_edges.append({"a": i, "b": b2})

## Geometry-fallback target picker. Returns the index of the best downstream
## node from `source_port`, or -1 if none is reachable. `exclude` lets a
## splitter's second edge avoid duplicating its first edge's target.
func _link_best_target(src_idx: int, source_port: Vector3, src_proc: String, exclude: int = -1) -> int:
	var candidates : Array = []
	for j in _nodes.size():
		if j == src_idx or j == exclude:
			continue
		var b: Dictionary = _nodes[j]
		var d : float = source_port.distance_to(b["win"] as Vector3)
		if d >= MAX_LINK_DIST:
			continue
		candidates.append([d, j])
	candidates.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	for cand in candidates:
		var best : int = int(cand[1])
		var b_proc : String = String(_nodes[best].get("process", ""))
		if _is_invalid_flow_direction(src_proc, b_proc):
			continue
		if _creates_cycle(best, src_idx):
			continue
		return best
	return -1

## #138 — return true when BOTH VSS_3A and VSS_3B input buffers are over the
## VSS_FULL_KG cap. C8 reads this every tick to decide its target direction.
## #139 — Pack-up cascade state. When both VSS_3A and VSS_3B are full there is
## nowhere for the intake to send material, so the upstream conveyors have to
## stop in sequence (one per ~1 s) all the way back up to the trilzeef. Track
## how long the both-full condition has held; the per-belt update routine pauses
## belt N once _pack_up_t exceeds N seconds (C11 first, then C10, …, then C1,
## finally the trilzeef and bunker paddle). The same timer drives the reverse:
## as soon as either VSS unblocks, the timer resets and belts restart in the
## opposite order (C1 first, working back down toward C11).
var _pack_up_t : float = 0.0
const _PACK_UP_GAP_S : float = 1.0           # seconds between successive belt pauses
const _PACK_UP_ORDER : Array[String] = [
	"transportband_11", "transportband_10", "transportband_9", "transportband_8_5",
	"transportband_8", "transportband_7", "transportband_6", "transportband_5",
	"transportband_4", "transportband_3", "transportband_2", "transportband_1",
	"trilzeef", "bunker",
]

## Whether belt id `bid` is currently in the pack-up paused zone, given the
## elapsed both-full duration. Belts come to a stop one-by-one from the head
## (C11) backwards toward the trilzeef + bunker.
func _is_pack_up_paused(bid: String) -> bool:
	if _pack_up_t <= 0.0:
		return false
	for i in _PACK_UP_ORDER.size():
		var when : float = float(i) * _PACK_UP_GAP_S
		if _pack_up_t < when:
			return false
		if bid == _PACK_UP_ORDER[i] or bid.begins_with(_PACK_UP_ORDER[i] + "_"):
			return true
	return false

## When only one VSS is full the switch belt's buffer-aware split (#137)
## already biases against it, so there's no need to flip C8 in that case.
## #211d — extended to ALSO trip pack-up when an upstream ShredderFeedBelt
## has latched an intake_overfill, belt_jam, or thermal_shutdown fault. A
## jammed/over-packed FEEDER stops being able to absorb material as fast as
## the trilzeef + bunker can push it, so the same cascade that triggers on
## "VSSs both full" must trigger on "feeder choked" — no new ordering, just
## a wider predicate. Internal C8-reverse logic still asks the precise
## VSS-only question through _both_vss_full_native().
func _both_vss_full() -> bool:
	return _both_vss_full_native() or _intake_overfilled() or _has_belt_jam_or_thermal()

## The original VSS-only predicate, kept intact so C8's reverse-target choice
## (per-edge loop ~line 1714) still asks the precise "both silos overfull"
## question. The widened _both_vss_full() above is for the pack-up cascade.
func _both_vss_full_native() -> bool:
	var vss_count : int = 0
	var vss_full  : int = 0
	for nd in _nodes:
		if String(nd.get("id", "")) != "vss_silo":
			continue
		vss_count += 1
		if float(nd.get("buffer", 0.0)) >= VSS_FULL_KG:
			vss_full += 1
	# Need at least two VSSs registered (3A + 3B). If only one is placed,
	# overflow logic can't trigger — fall back to forward-only.
	return vss_count >= 2 and vss_full == vss_count

## #211d — any ShredderFeedBelt in the scene reporting intake_overfill_active.
## Walks the "shredder_feed_belt" group (set in ShredderFeedBelt._ready) so the
## predicate works whether the feeder is parented under LineFlow or in
## arbitrary world-scene places (Line 3A vs sandbox vs macro-built layouts).
func _intake_overfilled() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for b in tree.get_nodes_in_group("shredder_feed_belt"):
		if b == null or not is_instance_valid(b):
			continue
		if b.has_method("intake_overfill_active") and bool(b.call("intake_overfill_active")):
			return true
	return false

## #211d — any ShredderFeedBelt reporting belt_jam OR thermal_shutdown. Belt
## jams are mechanically equivalent to intake overfill for cascade purposes
## (no material can leave the feeder either way) so we lump them in here.
func _has_belt_jam_or_thermal() -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for b in tree.get_nodes_in_group("shredder_feed_belt"):
		if b == null or not is_instance_valid(b):
			continue
		if b.has_method("belt_jam_active") and bool(b.call("belt_jam_active")):
			return true
		if b.has_method("thermal_shutdown_active") and bool(b.call("thermal_shutdown_active")):
			return true
	return false

## Semantic direction filter for the geometry-fallback linker (#78). Some
## (upstream_process, downstream_process) pairs are physically impossible and
## must NEVER be picked even if Euclidean-closest. Today this catches:
##   buffer → airsep  : silos never feed cyclones. Cyclones are pneumatic
##                      separators that drop material DOWN into silos under
##                      gravity, so flow is cyclone → silo, never the reverse.
##   buffer → buffer  : silo → silo would only ever be a misclick. Stop it.
##   airsep → airsep  : two cyclones in a row is a sign the linker got lost.
## Add more pairs here as new failure modes show up.
func _is_invalid_flow_direction(a_proc: String, b_proc: String) -> bool:
	if a_proc == "buffer" and b_proc == "airsep":
		return true
	if a_proc == "buffer" and b_proc == "buffer":
		return true
	if a_proc == "airsep" and b_proc == "airsep":
		return true
	return false

## Would adding edge from_idx → to_idx close a cycle? DFS from to_idx, walking
## existing _edges forward — if we can reach from_idx the new edge is rejected.
## Replaces the old single-step `_edge_exists(best, i)` check that only caught
## length-2 cycles and let longer ones (silo→A→cyclone→silo) through. (#78)
##
## #71 — recirc-flagged edges are INVISIBLE to this DFS. The 3A dry-loop closes
## a real cycle (cyclone → mengsilo) on purpose; if cycle prevention saw it,
## the main forward path out of mengsilo would also be blocked. Skipping
## recirc edges lets the loop coexist with normal forward links.
func _creates_cycle(from_idx: int, to_idx: int) -> bool:
	# Outgoing-edge map built once per call; n is small so this is cheap.
	var out_map : Dictionary = {}
	for e in _edges:
		if bool(e.get("recirc", false)):
			continue
		var src : int = int(e["a"])
		if not out_map.has(src):
			out_map[src] = []
		(out_map[src] as Array).append(int(e["b"]))
	var visited : Dictionary = {}
	var stack : Array = [from_idx]
	while not stack.is_empty():
		var cur : int = int(stack.pop_back())
		if cur == to_idx:
			return true
		if visited.has(cur):
			continue
		visited[cur] = true
		if out_map.has(cur):
			for nxt in out_map[cur]:
				stack.append(int(nxt))
	return false

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
## ALL conveying rotors of a machine — every direct child in the "mechanism"
## group that exposes current_rpm() (a RotatingMechanism). Multi-rotor
## machines (doseersilo's 3 augers, frictiewasser's 2 stirrers) MUST get
## set_running() driven on every one of them, otherwise only the first
## listed mechanism spins. Returns [] when the machine has no modelled rotor.
func _find_mechanisms(machine: Node) -> Array:
	var out : Array = []
	for c in machine.get_children():
		if c.is_in_group("mechanism") and c.has_method("current_rpm"):
			out.append(c)
	return out

## Backward-compat: the FIRST rotor in mechanism order. K-mode HUD widgets
## that show a single "primary" RPM read this — preserving the legacy
## "primary mechanism" semantics. Callers that need to drive ALL rotors
## (set_running cascade, spin gate) walk nd["mechs"] instead.
func _find_mechanism(machine: Node) -> Node:
	var list := _find_mechanisms(machine)
	return list[0] if not list.is_empty() else null

## The machine's FilmFlakeField visual layer (if it has one), for #173 coupling.
func _find_film_field(machine: Node) -> Node:
	for c in machine.get_children():
		if c.is_in_group("film_field") and c.has_method("set_live_state"):
			return c
	return null

## The machine's steam plume (GPUParticles in group "steam_plume"), searched
## recursively since it lives under the model subtree. Gated on real flow so an
## idle machine never steams (operator 2026-07-16: "inventing water from nothing").
func _find_steam_plume(machine: Node) -> Node:
	for c in machine.find_children("*", "GPUParticles3D", true, false):
		if c.is_in_group("steam_plume"):
			return c
	return null

## The extruder's heetafslag die-face strand switcher (meta die_face_switcher),
## searched recursively. Gated on real flow so an idle die shows no melt.
func _find_die_switcher(machine: Node) -> Node:
	for c in machine.find_children("*", "Node3D", true, false):
		if c.has_meta("die_face_switcher"):
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
	# #218 — DO NOT slam every node to powered=false / spin=0.0 here.
	# Survivors were rehydrated by rebuild() above; newly-discovered nodes
	# already carry the cold defaults from their fresh dict construction in
	# _discover(). Forcing zero would re-trigger a PLC spin-up on every HMI
	# placement, which is exactly what cold-spawn + state-preserving rebuild
	# is meant to avoid.
	#
	# #218 — SURVIVOR PRE-POWER. Walk the freshly-built stage list and mark
	# each PLC stage as already-powered when its node was running before
	# the rebuild. Without this, the per-tick override
	# `_nodes[ni]["powered"] = _plc.is_powered(stage)` would drop every
	# survivor back to false on the next tick — observable as the whole
	# line restart-flickering through a 20s downstream-first ramp every
	# time the operator drops a single HMI panel mid-shift. With pre-
	# power, the override returns true for survivor stages immediately
	# and only the truly cold (newly-placed) stages wait for the ramp.
	for stage in _plc_stage_node.size():
		var ni : int = int(_plc_stage_node[stage])
		if ni < 0 or ni >= _nodes.size():
			continue
		if bool(_nodes[ni].get("_survivor_powered", false)):
			_plc.set_stage_powered(stage, true)
	# Warm-boot path: the save loader called mark_warm_boot() so the line
	# must come up hot, no stagger. force_all_powered() walks every stage
	# and snaps it to running, matching the terminal state start() ends
	# in. auto_start (without _warm_boot) keeps the legacy staggered cold
	# start so a freshly built world still feels like a real power-up.
	if _warm_boot:
		_plc.force_all_powered()
	elif auto_start:
		_plc.start()
	_warm_boot = false   # consume the warm-boot one-shot

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
	if lid.find("doseersilo") >= 0:
		# A dosing silo has 3 parallel augers. Each contributes independently to
		# throughput — one running = 1/3 max, all three at the same Hz = 3× one.
		# Topology (see _component_topology) treats this as PARALLEL.
		out["auger_1"] = 1.0
		out["auger_2"] = 1.0
		out["auger_3"] = 1.0
	elif lid.find("flotation") >= 0 or lid.find("sink") >= 0:
		out["inlet"]       = 1.0
		out["transport_1"] = 1.0
		out["transport_2"] = 1.0
		out["outlet"]      = 1.0
	elif lid.find("blower") >= 0 or lid.find("ventilator") >= 0 or lid.find("cyclone") >= 0 or lid.find("sifter") >= 0:
		out["drive"] = 1.0
	elif lid.find("shredder") >= 0 or lid.find("mill") >= 0:
		out["rotor"] = 1.0
	elif lid.find("bunker") >= 0:
		# 2026-07-06 bunker rebuild (bunker.md): the machine is now a travelling
		# buffer CONVEYOR with ONE discharge bunkerrol (SWI-039), not a 4-roller
		# bank. The component KEY stays the legacy "uittrekrol" so old saves and
		# existing HMI addressing keep working (bunker.md flag F15) — the catalog
		# tags the new bunkerrol's RotatingMechanism with comp == "uittrekrol".
		# Documented names are "belt" (deck drive) + "bunkerrol"; rename here and
		# in the catalog together in a dedicated save-migration pass.
		# TODO(bunker interlock, bunker.md §3.3 / operator interview): shredder-2
		# `mol` trip → powered=false on the bunker's outfeed belt AND the bunker
		# itself; TITECH/TOMRA keep running. Distinct from (in addition to) the
		# #139 pack-up cascade where "bunker" stays last in _PACK_UP_ORDER.
		# TODO(relay trips, ruling B3 2026-07-06): speed settings BELOW 200
		# (settable, sim cap 1000) must fire relay-trip/motor-stall events
		# ~every 15 min, worse the lower — needs an event hook in the tick; the
		# catalog stamps `bunker_relay_trip_below` meta on the model meanwhile.
		out["uittrekrol"] = 1.0
	elif lid.find("nir") >= 0 or lid.find("tomra") >= 0 or lid.find("titech") >= 0:
		# NIR optical sorter — the acceleration belt drums are the driven part
		# (catalog tags the end drums with comp == "belt").
		out["belt"] = 1.0
	elif lid.find("friction_washer") >= 0 or lid.find("frictiewasser") >= 0:
		# Frictiewasser stirring tank — two independent vertical stirrer motors
		# (the catalog tags the shafts comp == "stirrer_1" / "stirrer_2").
		out["stirrer_1"] = 1.0
		out["stirrer_2"] = 1.0
	else:
		out["drive"] = 1.0
	return out

## Component topology — how the per-component RPMs combine into a single machine
## throughput multiplier:
##
##   "parallel"  — components add (each is an independent feeder; doseersilo
##                 augers, parallel pumps). Effective multiplier = AVG, which
##                 represents each component's 1/N share of the design throughput.
##   "series"    — components bottleneck (a tank's inlet/paddles/outlet have to
##                 all flow for material to move through; the slowest one limits
##                 throughput). Effective multiplier = MIN.
##   "single"    — only one component; min == avg, behaviour identical.
static func _component_topology(id: String) -> String:
	var lid := id.to_lower()
	if lid.find("doseersilo") >= 0:
		return "parallel"
	if lid.find("flotation") >= 0 or lid.find("sink") >= 0:
		return "series"
	if lid.find("friction_washer") >= 0 or lid.find("frictiewasser") >= 0:
		return "parallel"
	return "single"

## Lookup by placeable id — returns the FIRST match. A placeable id is a machine
## TYPE, not an address: Line 3C alone runs five friction_sep at four different
## calibrated currents, so this cannot address a specific machine. Kept only as
## the LEGACY fallback inside _resolve() for callers still holding a bare id.
## Empty dict if missing.
func _find_node_by_id(id: String) -> Dictionary:
	for nd in _nodes:
		if String(nd["id"]) == id:
			return nd
	return {}

## Resolve a machine HANDLE to its node dict. Exact match on the per-instance key
## first (nd["key"] — see the _code_conflicts declaration), then the legacy
## placeable-id fallback. Permissive on purpose: a strict resolver would return {}
## for every call site still passing a bare id and blank the MACHINES screen the
## day this lands. Empty dict when nothing matches.
func _resolve(handle: String) -> Dictionary:
	if handle == "":
		return {}
	for nd in _nodes:
		if String(nd.get("key", "")) == handle:
			return nd
	return _find_node_by_id(handle)

## Codes two nodes both tried to claim, as {code, kept, refused}. Empty on a
## healthy world; the tests assert it stays empty.
func code_conflicts() -> Array[Dictionary]:
	return _code_conflicts

## Public HMI surface — every setter quietly noops on an unknown handle so the
## panel can be opened before the line has been built without crashing.
func set_machine_hand_mode(id: String, on: bool) -> void:
	var nd := _resolve(id)
	if not nd.is_empty():
		nd["hand_mode"] = on
		if not on:
			nd["manual_on"] = false   # leaving HAND drops the manual run

func set_machine_manual_on(id: String, on: bool) -> void:
	var nd := _resolve(id)
	if not nd.is_empty() and bool(nd["hand_mode"]):
		nd["manual_on"] = on

func set_machine_rpm_pct(id: String, pct: float) -> void:
	var nd := _resolve(id)
	if not nd.is_empty():
		nd["rpm_pct"] = clampf(pct, 0.0, 1.0)   # 1.0 = rated max rpm
		_apply_rotor_rpm(nd)                     # physicalize: drive the visible spin

## Physically drive every TOP-LEVEL rotor of a machine from its rpm setting, so
## the VISIBLE spin speed matches the control (different setpoints → visibly
## different speeds). Rotors nested under another rotor (e.g. a drive-band riding
## a drum) are skipped — they ride their parent. The rotor list is cached per node.
func _apply_rotor_rpm(nd: Dictionary) -> void:
	var machine = nd.get("node")
	if machine == null or not is_instance_valid(machine):
		return
	if not nd.has("rotors"):
		var list : Array = []
		for m in machine.find_children("*", "", true, false):
			if not (m.is_in_group("mechanism") and ("nominal_rpm" in m)):
				continue
			# Skip rotors nested under another rotor (they ride their parent).
			var anc = m.get_parent()
			var nested := false
			while anc != null and anc != machine:
				if anc.is_in_group("mechanism"):
					nested = true
					break
				anc = anc.get_parent()
			if not nested:
				list.append(m)
		nd["rotors"] = list
	var f : float = clampf(float(nd.get("rpm_pct", 1.0)), 0.0, 1.0)
	for m in nd["rotors"]:
		if is_instance_valid(m):
			m.rpm = f * float(m.nominal_rpm)

func set_machine_component_pct(id: String, component: String, pct: float) -> void:
	var nd := _resolve(id)
	if nd.is_empty():
		return
	var c : Dictionary = nd["components"]
	if c.has(component):
		c[component] = clampf(pct, 0.0, 1.0)
		_apply_component_rotor(nd, component)   # physicalize THIS rotor only

## Drive the rotor(s) belonging to one HMI component (one motor) from its
## setting. Rotors tagged (meta "comp") with this component spin at pct × their
## nominal. If the machine has a single untagged drive, this component drives all
## its rotors (the single-motor case).
func _apply_component_rotor(nd: Dictionary, comp: String) -> void:
	var machine = nd.get("node")
	if machine == null or not is_instance_valid(machine):
		return
	var pct : float = clampf(float((nd["components"] as Dictionary).get(comp, 1.0)), 0.0, 1.0)
	var matched := false
	for m in machine.find_children("*", "", true, false):
		if not (m.is_in_group("mechanism") and ("nominal_rpm" in m)):
			continue
		if m.has_meta("comp") and String(m.get_meta("comp")) == comp:
			m.rpm = pct * float(m.nominal_rpm)
			matched = true
	if not matched:
		# Single-drive machine: this component governs all its rotors.
		nd["rpm_pct"] = pct
		_apply_rotor_rpm(nd)

## {component → its rotor's rated max rpm}, for the HMI sliders. Untagged
## components default to the machine's primary max.
func _component_max_rpms(nd: Dictionary) -> Dictionary:
	var out := {}
	var default_max := _machine_max_rpm(nd)
	for k in (nd.get("components", {}) as Dictionary).keys():
		out[k] = default_max
	var machine = nd.get("node")
	if machine != null and is_instance_valid(machine):
		for m in machine.find_children("*", "", true, false):
			if m.is_in_group("mechanism") and m.has_meta("comp") and ("nominal_rpm" in m):
				out[String(m.get_meta("comp"))] = maxf(float(m.nominal_rpm), 1.0)
	return out

## Returns a snapshot the HMI can render: live state + override state + components.
## `id` is a HANDLE: the per-instance key (preferred) or a legacy bare placeable
## id (first match). The payload echoes the key back so a caller can tell WHICH
## instance answered, plus the plant address and the calibrated nominal current
## the live `amps` is derived from.
func get_machine_info(id: String) -> Dictionary:
	var nd := _resolve(id)
	if nd.is_empty():
		return {}
	return {
		"id":         String(nd["id"]),
		"key":        String(nd.get("key", "")),
		"l3c_code":   String(nd.get("l3c_code", "")),
		"amps_nominal": float(nd.get("amps_nominal", 0.0)),
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
		"max_rpm":    _machine_max_rpm(nd),
		"comp_max_rpm": _component_max_rpms(nd),
		"components": (nd.get("components", {}) as Dictionary).duplicate(),
	}

## The rated max rpm the HMI slider should top out at — the primary rotor's
## nominal_rpm (the real visible spin rate). Falls back to 100 if no rotor.
func _machine_max_rpm(nd: Dictionary) -> float:
	var mech = nd.get("mech")
	if mech != null and is_instance_valid(mech) and ("nominal_rpm" in mech):
		return maxf(float(mech.nominal_rpm), 1.0)
	return 100.0

## Every machine on the line as a flat list for the MACHINES screen list. One row
## per NODE, and `key` is the handle to pass back to get_machine_info / the
## setters — `id` alone cannot address a machine (it is the model, and duplicates
## are normal). `label` is display-only: the plant tag when the machine has one,
## otherwise "<name> #<n>" so two blowers no longer render as the same row.
func machine_list() -> Array:
	var out : Array = []
	for nd in _nodes:
		var k := String(nd.get("key", ""))
		var code := String(nd.get("l3c_code", ""))
		var label := code
		if label == "":
			label = k.replace("_", " ").replace("#", " #")
		out.append({
			"id":       String(nd["id"]),
			"key":      k,
			"l3c_code": code,
			"label":    label,
			"role":     String(nd["role"]),
			"process":  String(nd["process"]),
		})
	return out

## Combine a node's component_pct entries into a single throughput multiplier per
## that machine's topology (parallel → avg = each component's 1/N contribution;
## series → min = slowest component bottlenecks the whole flow; single → trivial).
## 1.0 if no components defined.
func _component_pct_multiplier(nd: Dictionary) -> float:
	var c : Dictionary = nd.get("components", {})
	if c.is_empty():
		return 1.0
	var top := _component_topology(String(nd.get("id", "")))
	if top == "series":
		var lo := 999.0
		for k in c:
			lo = minf(lo, float(c[k]))
		return lo
	# parallel + single both behave as avg (single has one element, so they match).
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

## Same fault, as the per-instance KEY. estop_fault_id() names a machine TYPE, so
## on a line with five friction separators it cannot say which one tripped; this
## can. Both exist because the internal alarm text at :1693 still emits the id.
func estop_fault_key() -> String:
	if _estop_active and _estop_fault_node >= 0 and _estop_fault_node < _nodes.size():
		return String(_nodes[_estop_fault_node].get("key", ""))
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
## metered stage's calibrated draw (#173). Only stages carrying an l3c_code are
## metered, i.e. only a world where the `line_3c` macro has been placed; a 3A/3B/1
## world reads whatever MotorOverload puts on its high-load drives and nothing
## else. ProcessModel.line_nominal_amps() (488.49 A) is the FULL-LOAD sum of the
## whole 3C spine and is what this approaches at load_frac 1.0 — not a figure any
## other line reaches.
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
	# #139 — pack-up cascade timer. Tick UP while both VSSs are full so the
	# downstream pause sequence (C11 → … → C1 → trilzeef → bunker) marches one
	# belt per _PACK_UP_GAP_S. Reset to 0 the moment either VSS frees up so the
	# belts restart in reverse order (C1 first → C11 last → trilzeef + bunker).
	if _both_vss_full():
		_pack_up_t += delta
	else:
		_pack_up_t = 0.0

	# Cache spatial queries once per tick for heavy inner loops like _dump_waste
	# and the feed bale-pickup scan.
	var tree = get_tree()
	if tree != null:
		_floor_piles_cache = tree.get_nodes_in_group("floor_pile")
		_waste_containers_cache = tree.get_nodes_in_group("waste_container")
		_bales_cache = tree.get_nodes_in_group("bale")
	else:
		_floor_piles_cache.clear()
		_waste_containers_cache.clear()
		_bales_cache.clear()

	# 0) PLC powers the line up DOWNSTREAM-FIRST; each powered machine then ramps
	#    its rotor over SPIN_UP_S. The live spin (0..1) gates how fast it conveys,
	#    so nothing moves until the rotor is actually turning (#145).
	if _plc != null:
		_plc.tick(delta)
		for stage in _plc_stage_node.size():
			var ni : int = int(_plc_stage_node[stage])
			# #218 — SURVIVOR-AWARE override. A survivor stage carries
			# `_survivor_powered = true` from rebuild() rehydration; we
			# do NOT let the PLC override that until the PLC catches up
			# (is_powered(stage) reports true on its own). Once it does,
			# clear the flag and the stage falls back to normal PLC
			# governance for the rest of its life. This is what keeps
			# jogging / placing / deleting an unrelated machine from
			# observably restarting the entire line.
			var plc_says : bool = _plc.is_powered(stage)
			var nd_t : Dictionary = _nodes[ni]
			if bool(nd_t.get("_survivor_powered", false)):
				if plc_says:
					nd_t["_survivor_powered"] = false   # PLC caught up
				nd_t["powered"] = true
			else:
				nd_t["powered"] = plc_says
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
		# Multi-rotor cascade: walk EVERY mechanism child, not just the
		# first one. Without this, doseersilo (3 augers) + frictiewasser
		# (2 stirrers) only see their primary rotor respond to PLC power,
		# so e.g. only stirrer_1 visibly spins on a frictiewasser even
		# though the LineFlow node is fully powered.
		var mechs_s : Array = nd_s.get("mechs", [])
		if mechs_s.is_empty():
			# Survivor dict from a pre-mechs save — fall back to the
			# legacy single-rotor pointer so we don't drop the cascade.
			var single_mech = nd_s.get("mech")
			if single_mech != null and is_instance_valid(single_mech) \
					and single_mech.has_method("set_running"):
				single_mech.call("set_running", bool(nd_s["powered"]))
		else:
			for m in mechs_s:
				if m != null and is_instance_valid(m) and m.has_method("set_running"):
					m.call("set_running", bool(nd_s["powered"]))
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
		# Flow-gated emitters: material actually moving through this machine?
		var flowing_s : bool = float(nd_s["thru"]) > 0.001
		var plume_s = nd_s.get("plume")
		if plume_s != null and is_instance_valid(plume_s):
			plume_s.emitting = flowing_s
		var die_s = nd_s.get("die_switcher")
		if die_s != null and is_instance_valid(die_s):
			PlaceableCatalog.show_die_face_state(die_s, 1 if flowing_s else -1)

	# 1) Feed — OFF unless deliberately enabled. When on, a head node draws from a
	#    bale on its feed point and DEPLETES that bale (finite); the bale is removed
	#    when empty, so the line can never feed from thin air or forever.
	# #24 — a head node prefers the NEAREST WorldLayout.line_starts marker over its
	#    own world position as the feed-point. This decouples the intake-marker
	#    drop zone (where the forklift parks the bale) from the head machine itself,
	#    which sits a few metres inside the building. If no marker is within
	#    LINE_START_MARKER_RADIUS, fall back to the head machine's own position
	#    (legacy behaviour — preserves the test rigs that just plopped a bale on a
	#    machine).
	if feed_enabled:
		var bales := _bales_cache
		for i in _nodes.size():
			var nd: Dictionary = _nodes[i]
			if String(nd["role"]) == "sink" or _has_incoming(i):
				continue
			# A node dict can outlive its Node3D: anything that frees a placed
			# machine WITHOUT an immediate rebuild() (a save-reload cycle, a scripted
			# teardown) leaves this array holding freed objects for a tick or more.
			# The `as Node3D` cast below then throws "Trying to cast a freed object",
			# which ABORTS tick() at this line — so every observer after it
			# (_tick_advanced_systems: MotorOverload, extruder, dryer pairs) silently
			# stops running for the rest of the session. Same guard, same reason as
			# _silo_feed_multiplier (:397-407). Skipping is conserving: a head whose
			# machine no longer exists cannot draw from a bale.
			var head_node = nd.get("node", null)
			if head_node == null or not is_instance_valid(head_node):
				continue
			var feed_point : Vector3 = _head_feed_point(head_node as Node3D)
			var bale := _bale_at(feed_point, bales)
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
			# #223 audit: as material feeds off the bale, its PHYSICS mass drops too
			# — a half-consumed bale weighs half, so the clamp/forklift and any
			# shove feel the depletion (not a full-weight husk). remaining_kg starts
			# at the full estimated_weight, so this tracks it 1:1 down to a 1 kg floor.
			if bale is RigidBody3D:
				(bale as RigidBody3D).mass = maxf(remaining, 1.0)
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
		# #52 per-tick load bookkeeping for the motor-overload observer. These are
		# pure OBSERVATIONS of the existing split (set below), never inputs to it.
		nd["_backlog_kg"] = 0.0
		nd["_moved_kg"]   = 0.0
		if bin.mass_kg <= 0.0:
			nd["thru"] = lerpf(float(nd["thru"]), 0.0, 0.2)   # spin down when starved
			continue
		# Effective conveying rate is GATED by live rotation: design rate × spin-up
		# × rotor rpm-fraction. A stopped or still-spinning-up rotor moves nothing,
		# so material backs up in this machine's input buffer (#145).
		# Effective rate = design × spin × mech × HMI overrides (rpm slider AND the
		# avg of the per-component RPMs — inlet/transports/outlet for tanks).
		var rate_mul : float = float(nd.get("rpm_pct", 1.0)) * _component_pct_multiplier(nd)
		var eff_rate: float = float(nd["rate"]) * float(nd["spin"]) * _mech_fraction(nd) * rate_mul
		# #52 air gating — an air-driven consumer (TITECH ejector / PCU ram) starved of
		# header pressure conveys slower. This is a GENTLE rate multiplier only: it
		# slows flow, the un-moved mass simply backs up in the buffer (conserving). At
		# full pressure consumer_air_factor()==1.0 and nothing changes.
		if String(nd.get("air_id", "")) != "":
			eff_rate *= _air_factor()
		# NIR shaft-wrap penalty (TITECH/TOMRA only). Below TRIP_WRAP_G the
		# multiplier is 1.0 and this is a no-op; once tripped it lerps 1.0 → 0.5
		# as wrap fills to FULL_WRAP_G. Like the air gate, the un-moved mass
		# simply backs up in the buffer (conserving). The controller's own tick
		# runs AFTER the split below so it accumulates on what actually moved,
		# not the design rate.
		var nir_ctrl = nd.get("nir_ctrl")
		if nir_ctrl != null and is_instance_valid(nir_ctrl):
			eff_rate *= float(nir_ctrl.throughput_multiplier())
		# ── STOP-WITH-RESIDUAL CONTRACT (operator-confirmed "leegdraaien" cascade) ──
		# When a machine is stopped (PLC power off, HAND-mode manual_on=false, E-stop
		# upstream cut, MotorOverload trip, CutterCompactor Donut stall, or the
		# pack-up cascade), nd["powered"] flips false → nd["spin"] decays toward 0 →
		# eff_rate falls through this threshold → we `continue` WITHOUT calling
		# bin.split_mass(), so `bin` (the input buffer / residual material) is
		# UNTOUCHED. Nothing flushes to nd["out"], nothing leaks downstream from
		# this machine's buffer, no kg disappears. On restart, spin ramps back up
		# and the same `bin` is processed first before the pipe delivers any new
		# upstream material. This is what makes the operator's "leegdraaien" cascade
		# emerge naturally from material conservation: input feed stops at the head
		# (feed_enabled=false or upstream stopped) → each downstream machine keeps
		# running and drains its OWN buffer through its discharge rate → the next
		# machine downstream starves in sequence as the pipe between them empties.
		# Do not "flush on stop" or "clear buffer on stop" — that would break both
		# the conservation ledger AND the realistic empty-out behaviour.
		if eff_rate <= 0.0001:
			# Stopped/starved this tick: the whole buffer is un-passed backlog.
			# bin is intentionally NOT modified — material is preserved for restart.
			nd["_backlog_kg"] = bin.mass_kg
			nd["thru"] = lerpf(float(nd["thru"]), 0.0, 0.2)
			continue
		var flow := bin.split_mass(minf(eff_rate * delta, bin.mass_kg))
		# Observe (don't alter) the split: what moved on vs what stayed behind.
		nd["_moved_kg"]   = flow.mass_kg
		nd["_backlog_kg"] = bin.mass_kg

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

	# 2.5) ADVANCED-SYSTEM OBSERVERS (#52) — run ALONGSIDE the flow now that each
	#      node's throughput/backlog for this tick is known. Nothing here re-routes
	#      material or changes the split; the extruder/MFI models publish telemetry,
	#      the motor-overload model can only STOP a jammed rotor conveying (mass then
	#      backs up — conserving), and air duty is reported to the header.
	_tick_advanced_systems(delta)
	# 2.6) #99 — DRD batch dryer cycles. Step both drums of every registered
	#      pair (and any unpaired single drum) so the L/R BEFULLEN swap is
	#      driven by real elapsed time. The router (section 3 below) reads
	#      cycle.step on the same tick to decide which drum receives flake.
	_tick_dryer_pairs(delta)

	# 3) Carry each output DOWN ITS CONNECTOR as a delay-line. Material entering a
	#    link rides PIPE_STAGES slots that shift forward one slot every stage_dt,
	#    so it takes the full transit_time to reach the downstream machine. Feeding
	#    the head therefore CANNOT appear instantly at the sink (#145).
	# Pre-compute per-edge take-fractions. Non-splitter sources keep the old
	# even-split-by-branch-count behaviour (1/N per branch — first edge takes
	# 1/N, second takes 1/(N-1) of what remains, last takes everything left).
	# Splitter sources (#97) use a BUFFER-AWARE share instead: each downstream's
	# share is weighted by its remaining headroom (capacity - current buffer),
	# so an empty silo pulls more material than a near-full one. Falls back to
	# the even split when BOTH downstreams are full (no preference).
	#
	# Share → take-fraction conversion: split_fraction() mutates the source,
	# so the i'th edge takes `shares[i] / (1 - sum(shares[0..i-1]))` of what's
	# left rather than `shares[i]` of the original. This keeps the per-branch
	# bookkeeping the same as the old code while honouring biased shares.
	var _edge_take : Array = []
	_edge_take.resize(_edges.size())
	for ti in _edges.size():
		_edge_take[ti] = 1.0
	var _src_to_edges : Dictionary = {}
	for ti in _edges.size():
		var src_id := int(_edges[ti]["a"])
		var lst : Array = _src_to_edges.get(src_id, [])
		lst.append(ti)
		_src_to_edges[src_id] = lst
	for src_id in _src_to_edges.keys():
		var src_edges : Array = _src_to_edges[src_id]
		var n_branches : int = src_edges.size()
		if n_branches == 0:
			continue
		var src_node : Dictionary = _nodes[int(src_id)]
		var is_splitter : bool = String(src_node.get("role", "")) == "splitter" and n_branches >= 2
		var shares : Array = []
		if is_splitter:
			# weight_i = max(eps, 1 - downstream_buffer_kg / SPLITTER_CAP_KG)
			# Empty downstream → weight 1.0, fully-loaded → weight eps. Linear in
			# between. eps>0 keeps the splitter alive even when both downstreams
			# are full (falls back to ~even split because both eps's are equal).
			var weights : Array = []
			var total : float = 0.0
			for ei in src_edges:
				var dst : Dictionary = _nodes[int(_edges[ei]["b"])]
				var buf : float = float(dst.get("buffer", 0.0))
				var w : float = maxf(SPLITTER_SHARE_EPS,
					1.0 - buf / SPLITTER_CAPACITY_KG)
				weights.append(w)
				total += w
			for wi in n_branches:
				shares.append(float(weights[wi]) / total if total > 0.0 \
					else 1.0 / float(n_branches))
			# #137 — switch belt jog overlay. Only applies when the source has a
			# SwitchBelt controller AND exactly two downstreams (the standard
			# VSS_3A / VSS_3B Y). We write the target jog from the buffer-aware
			# share above, but READ the CURRENT (lagged) jog position for the
			# actual material split — so the deck has to physically slide before
			# the routing changes. That's the operator's spec: "10 cm/s, smooth
			# blend; the belt moves first, the flow follows."
			var ctrl = src_node.get("switch_ctrl")
			if ctrl != null and n_branches == 2:
				ctrl.set_jog_target(SwitchBeltScript.jog_target_for_share(float(shares[0])))
				var lagged : float = ctrl.share_to_first_from_jog()
				shares[0] = lagged
				shares[1] = 1.0 - lagged
			# #138 — C8 bidirectional overlay. Forward edge takes share_forward()
			# (= max(direction_x, 0)); reverse edge takes share_reverse(). Both
			# sum to abs(direction_x), so when the belt is mid-ramp (direction_x
			# ≈ 0) shares sum to <1 and material stalls in C8's buffer — that's
			# the "belt stopped" moment the operator described. Target direction
			# is read from VSS_3A + VSS_3B buffer levels: both above VSS_FULL_KG
			# → reverse, else → forward.
			var c8 = src_node.get("c8_ctrl")
			if c8 != null and n_branches == 2:
				# #211d — C8 reverses on the strict "both VSS full" condition,
				# NOT on the widened pack-up predicate. A jammed feeder belt
				# downstream of C8 shouldn't make C8 reverse — pack-up will
				# stop its upstream feed (#139) and that's enough.
				var both_full : bool = _both_vss_full_native()
				c8.set_direction_target(-1.0 if both_full else 1.0)
				# By convention wout (the FORWARD port +Z) is edge index 0,
				# wout2 (reverse) is edge index 1 — that's the order the linker
				# emits them per #54.
				shares[0] = c8.share_forward()
				shares[1] = c8.share_reverse()
		else:
			for _wi in n_branches:
				shares.append(1.0 / float(n_branches))
		# #99 — DRD pair routing overlay. If this source's two downstreams are
		# the L/R mech-dryer pair, override the share so 100% goes to whichever
		# drum is currently in BEFULLEN (instead of an even 50/50 split). This
		# is what makes the antiphase batch cycle visible upstream: one dryer
		# accepts the full feed while the other dries; they swap every soak.
		# Applied AFTER the splitter/SwitchBelt/C8 overlays so the pair routing
		# wins — none of those source types feed the dryer pair anyway, so this
		# never conflicts with the upstream Y/jog mechanisms.
		shares = _maybe_apply_dryer_pair_routing(src_edges, shares)
		var cum : float = 0.0
		for i in n_branches:
			var s : float = float(shares[i])
			if cum >= 0.99999:
				_edge_take[src_edges[i]] = 1.0
			else:
				_edge_take[src_edges[i]] = clampf(s / (1.0 - cum), 0.0, 1.0)
			cum += s

	var _out_left : Dictionary = {}
	for e2 in _edges:
		var ai2 := int(e2["a"])
		_out_left[ai2] = int(_out_left.get(ai2, 0)) + 1
	for ei in _edges.size():
		var e : Dictionary = _edges[ei]
		var an: Dictionary = _nodes[int(e["a"])]
		var bn: Dictionary = _nodes[int(e["b"])]
		var pipe: Array = e["pipe"]
		var src := int(e["a"])
		var rem : int = int(_out_left[src])
		# Inject this branch's SHARE of the source's output into the entry slot.
		var aout: MaterialBatch = an["out"]
		var take : float = float(_edge_take[ei])
		# #A3 — SILO LEVEL SENSOR SURGE WIRING. If the downstream is a silo with
		# a registered SiloLevelSensor, multiply this edge's take by the sensor's
		# effective_feed_multiplier(). Operator anecdote: the sensor's wire IS the
		# governor — when intact and the silo is climbing, it commands the wash-
		# line PLC to throttle feed (multiplier → 0.0; parcel parks in `aout` and
		# backs up at the source, conserving). When the operator bridges the
		# sensor it never says full and the upstream runs wide open (multiplier
		# → 1.5, surge ceiling, capped by the upstream's own mechanical max).
		# We CAP the effective take at 1.0 so we can never pull more material
		# than exists in `aout` this tick; the 1.5× expresses itself as this
		# edge greedily consuming ALL of `aout` instead of its fair share,
		# which propagates upstream-feed-rate increases tick by tick.
		var silo_mul : float = _silo_feed_multiplier(bn.get("node"))
		if silo_mul <= 0.0001:
			# Governor closed: don't inject this tick. Parcel stays in `aout`
			# and the SOURCE (e.g. the wash-line head) backs up — matches the
			# real PLC interlock closing the silo's metering damper.
			_out_left[src] = rem - 1
			continue
		if silo_mul > 1.0:
			take = clampf(take * silo_mul, 0.0, 1.0)
		if aout.mass_kg > 0.0 and rem > 0:
			if rem <= 1 or take >= 0.99999:
				(pipe[0] as MaterialBatch).add(aout)          # last/only branch takes the rest
				an["out"] = MaterialBatch.new()
			else:
				(pipe[0] as MaterialBatch).add(aout.split_fraction(take))
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

	# #52 push live line state + key process params to the SCADA dashboard (throttled).
	_push_scada(delta)

	_update_label()

# ── #52 advanced-system per-tick observers ────────────────────────────────────
## Step each attached observer for one tick. Order matters for the extruder pair:
## ExtruderScrew first (computes die_pressure/melt_temp/viscosity), THEN MfiProxy
## reads those. MotorOverload consumes the per-tick backlog/moved bookkeeping. Air
## duty is reported per air-driven consumer. Everything is guarded + conserving.
func _tick_advanced_systems(delta: float) -> void:
	# Per-consumer summed throughput (kg/s), so a duty is reported per air id even if
	# several machines share it. duty is normalised against the machine design rate.
	var air_duty : Dictionary = {}
	for nd in _nodes:
		# 1) EXTRUDER thermal/rheology — drive rpm from the live rpm_pct × screw max,
		#    feed it the current throughput, integrate, then read its published melt
		#    state onto the node (for the HMI / SCADA). Runs ALONGSIDE — the material
		#    still flows through the extruder node exactly as before.
		var ex = nd.get("ex")
		if ex != null:
			ex.call("set_rpm", float(nd.get("rpm_pct", 1.0)) * EXTRUDER_SCREW_MAX_RPM)
			ex.call("set_throughput", float(nd["thru"]))
			ex.call("tick", delta)
			nd["die_pressure"] = float(ex.get("die_pressure"))
			nd["melt_temp"]    = float(ex.get("melt_temp"))
			nd["viscosity"]    = float(ex.get("viscosity"))
			# 2) MFI soft-sensor — pure/instantaneous. Q in kg/h (thru kg/s × 3600);
			#    the proxy reads the extruder's die pressure (bar) + melt temp (°C; it
			#    treats a >20 value as a temperature and converts via η(T) internally).
			var mfi = nd.get("mfi")
			if mfi != null:
				nd["mfi_value"] = float(mfi.call("update",
					float(nd["thru"]) * 3600.0,
					float(ex.get("die_pressure")),
					float(ex.get("melt_temp"))))
		# #52 CUTTER-COMPACTOR — drive disc rpm + dosing gate from rpm_pct, synthesise
		# a feed batch sized to the LIVE throughput so the model's load fraction
		# tracks reality (pure-RefCounted CutterCompactor is fed a snapshot batch and
		# the discharge it produces is discarded — material accounting is already done
		# by LineFlow's normal in→out path). Donut stall drops `powered` so the node
		# stops conveying (the unmoved mass simply backs up — conserving). Motor amps
		# come from the model so the HMI shows real load on the compactor's spindle.
		var cc = nd.get("cc")
		if cc != null:
			var rpm_pct : float = float(nd.get("rpm_pct", 1.0))
			cc.call("set_rpm", rpm_pct * CC_NOMINAL_RPM)
			cc.call("set_dosing_gate", clampf(rpm_pct, 0.0, 1.0))
			var thru_kg : float = float(nd["thru"]) * delta
			if thru_kg > 0.0:
				var batch : MaterialBatch = MaterialBatch.new(thru_kg,
					thru_kg / FEED_DENSITY, DEFAULT_COMP.duplicate(), "cc_in",
					thru_kg * 0.08, 0.0)
				cc.call("feed", batch)
			cc.call("tick", delta)
			var _drained = cc.call("discharge", delta)   # discard — flow tracked by LineFlow
			nd["pot_temp"]    = float(cc.get("pot_temperature"))
			nd["cc_band"]     = String(cc.call("band"))
			nd["cc_fill_eff"] = float(cc.get("screw_fill_efficiency"))
			if bool(cc.get("stalled")):
				nd["powered"] = false             # Donut stall halts the drive
			nd["amps"] = float(cc.get("motor_amps"))
		# 3) MOTOR-OVERLOAD — pile on the un-passed backlog, relieve what moved on,
		#    advance the trip clock. A sustained overload trips the relay; we then drop
		#    this node's `powered` so it stops CONVEYING (material backs up — conserving).
		#    The model raises its own EventBus alarm on the trip edge.
		var mol = nd.get("mol")
		if mol != null:
			# Keep the model's run-state in step with the node so a stopped/E-stopped
			# drive accrues no trip time, and a re-powered one re-energises.
			if mol.has_method("set_running") and not bool(mol.call("is_tripped")):
				mol.call("set_running", bool(nd["powered"]))
			mol.call("add_load", float(nd.get("_backlog_kg", 0.0)))
			mol.call("relieve", float(nd.get("_moved_kg", 0.0)))
			mol.call("tick", delta)
			if bool(mol.call("is_tripped")):
				nd["powered"] = false           # stop conveying (conserving)
				nd["amps"]    = float(mol.get("current_amps"))   # 0 A while tripped
			else:
				# Mirror the live motor current onto the node so the HMI/SCADA amp
				# readout reflects the binding load on these high-load drives.
				nd["amps"] = float(mol.get("current_amps"))

		# NIR SHAFT-WRAP — accumulate fibrous wrap on the sorter shaft from the
		# material that ACTUALLY MOVED this tick (_moved_kg). Using moved (not the
		# design rate or the unmoved backlog) keeps the wrap honest: a stopped
		# sorter accumulates nothing, a half-flow sorter grows wrap at half speed.
		# tick() also updates the alarm edge + drives the visual cylinder
		# catalog-side, so all the wrap state stays inside the controller.
		var nir_ctrl_o = nd.get("nir_ctrl")
		if nir_ctrl_o != null and is_instance_valid(nir_ctrl_o):
			# `thru` is already EMA-smoothed kg/s and lives on the node; we use
			# it instead of _moved_kg/dt so the wrap growth tracks the same
			# throughput the HMI shows. `delta` here is the func parameter at
			# the top of _tick_advanced_systems.
			nir_ctrl_o.tick(delta, float(nd["thru"]))

		# #139 — pack-up cascade: when both VSSs full, conveyors pause one-per-
		# second from the head (C11) back toward the bunker. This is the actual
		# pause application — _is_pack_up_paused() advances with _pack_up_t.
		if _is_pack_up_paused(String(nd.get("id", ""))):
			nd["powered"] = false

		# 4) AIR consumer duty — accumulate this consumer's load fraction (throughput
		#    vs its design rate) so we can report a single duty per air id.
		var aid : String = String(nd.get("air_id", ""))
		if aid != "":
			var rate : float = float(nd["rate"])
			# Renamed from `load` — that shadows the built-in load() function.
			var air_load : float = clampf(float(nd["thru"]) / rate, 0.0, 1.0) if rate > 0.0 else 0.0
			air_duty[aid] = maxf(float(air_duty.get(aid, 0.0)), air_load)
	# Report the per-consumer duty to the header (drives its demand → pressure).
	var air := _air_network()
	if air != null and air.has_method("set_consumer_duty"):
		for aid in air_duty:
			air.call("set_consumer_duty", aid, float(air_duty[aid]))

## Push live state + key process parameters to the SCADA dashboard MainWorld owns.
## Throttled to ~6 Hz. Everything guarded so it no-ops without a dashboard or when a
## system/node is absent. Bands are picked so a healthy line stays grey (ISA-101).
func _push_scada(delta: float) -> void:
	if _scada == null or not is_instance_valid(_scada):
		return
	_scada_push_accum += delta
	if _scada_push_accum < SCADA_PUSH_DT:
		return
	_scada_push_accum = 0.0
	# State: Fault (E-stop) > Starting (PLC sequencing) > Running (any machine
	# powered) > Idle. set_state also drives the dashboard's micro-stop logger.
	if _scada.has_method("set_state"):
		var state := "Idle"
		if is_estopped():
			state = "Fault"
		elif is_line_starting():
			state = "Starting"
		elif line_powered_fraction() > 0.0:
			state = "Running"
		_scada.call("set_state", state)
	if not _scada.has_method("set_param"):
		return
	# Line amps — the summed live draw across every metered stage.
	_scada.call("set_param", "line_amps", live_line_amps(), 0.0, 520.0, "Line Current  (A)")
	# Granulaat quality — mass-weighted grade of all product this run.
	_scada.call("set_param", "gran_q", granulaat_quality(), 80.0, 100.0, "Granulaat Q  (/100)")
	# Extruder melt temp + MFI from the first extruder node that has the models.
	var ex_nd := _first_extruder_node()
	if not ex_nd.is_empty():
		_scada.call("set_param", "melt_temp", float(ex_nd.get("melt_temp", 0.0)), 185.0, 205.0, "Melt Temp  (C)")
		_scada.call("set_param", "mfi", float(ex_nd.get("mfi_value", 0.0)), 0.3, 2.0, "MFI  (g/10min)")
	# Header air pressure from the AirNetwork autoload.
	var air := _air_network()
	if air != null and ("current_pressure_bar" in air):
		_scada.call("set_param", "air_bar", float(air.get("current_pressure_bar")), 5.5, 8.0, "Air Header  (bar)")
	# #52 — Cutter-compactor pot temperature from the first compactor node carrying
	# the thermo model. The sweet-spot band (100..105 °C) is the green zone; cooler
	# = UNDERHEATED, hotter = DONUT-STALL imminent. Operator's job is to keep it here.
	var cc_nd := _first_cc_node()
	if not cc_nd.is_empty():
		_scada.call("set_param", "cc_pot", float(cc_nd.get("pot_temp", 0.0)), 100.0, 105.0, "Compactor Pot  (C)")
		# #scada-surfacing — softstarter PLC budget gauge. Operator pushes
		# kW past the 240 kW baseline and the budget integrates kW·s. Trip
		# at 300 kW·s. Nominal band stays in the lower half (0..150 kW·s);
		# above 150 → caution alarm so the operator notices BEFORE the trip.
		var cc = cc_nd.get("cc")
		if cc != null and "softstarter_budget_kws" in cc:
			_scada.call("set_param", "cc_softstarter",
				float(cc.softstarter_budget_kws),
				0.0, 150.0,
				"PCU Softstarter  (kW·s)")
		# Unified PCU cause-of-stop status string. Sits alongside the extruder's
		# fault_reason text param on the SCADA so the operator sees BOTH the
		# extruder and the compactor cause-of-stop on the same panel — the
		# "unified HMI" view. Empty when the compactor is running normally;
		# "SOFTSTARTER TRIP" / "DONUT STALL" / "PROCESS UNSTABLE" when alarmed.
		if cc != null and cc.has_method("cause_of_stop") \
				and _scada.has_method("set_text_param"):
			var cause : String = String(cc.call("cause_of_stop"))
			var alarming : bool = false
			if cc.has_method("is_alarming"):
				alarming = bool(cc.call("is_alarming"))
			else:
				alarming = cause != ""
			_scada.call("set_text_param", "cc_status",
				cause, alarming, "PCU Status")

## The first extruder node carrying the thermal/MFI models, or {} if none placed.
func _first_extruder_node() -> Dictionary:
	for nd in _nodes:
		if nd.get("ex") != null:
			return nd
	return {}

## #52 — first node carrying a CutterCompactor model, or {} if none placed.
func _first_cc_node() -> Dictionary:
	for nd in _nodes:
		if nd.get("cc") != null:
			return nd
	return {}

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

## #24 — resolve the head node's effective feed-point. Prefers the NEAREST
## WorldLayout.line_starts marker within LINE_START_MARKER_RADIUS of the head
## machine; falls back to the head's own world position when no marker is in
## range. This is what lets a forklift drop a bale on the user-marked intake
## (10-15 m from the actual head machine) and have the line consume it.
func _head_feed_point(head: Node3D) -> Vector3:
	var head_pos : Vector3 = head.global_position
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		return head_pos
	var starts = wl.get("line_starts")
	if not (starts is Dictionary) or (starts as Dictionary).is_empty():
		return head_pos
	var best_pos : Vector3 = head_pos
	var best_d : float = LINE_START_MARKER_RADIUS
	for v in (starts as Dictionary).values():
		if not (v is Vector3):
			continue
		# Marker lives in LAYOUT FRAME (player_spawn-relative, north-up); convert
		# to the SCENE FRAME (rotated by world_yaw + anchored on player spawn)
		# before measuring distance to the world-frame head_pos.
		var marker : Vector3 = _layout_marker_to_scene(v)
		var d : float = marker.distance_to(head_pos)
		if d < best_d:
			best_d = d
			best_pos = marker
	return best_pos

## Map a raw WorldLayout marker to its scene position through MainWorld's
## `_layout_to_scene`. Markers are SCENE-ABSOLUTE, so that call is the XZ
## identity today — but it stays the single choke point so the frame is
## defined in exactly one file (WorldFrame.gd) rather than assumed here.
##
## NOTE — this path was INERT while the transform rotated+anchored: line_starts
## landed 145-175 m from any head, so nothing ever matched
## LINE_START_MARKER_RADIUS and every head silently used its own position. The
## snap is live again now; a head can legitimately move up to that radius.
func _layout_marker_to_scene(marker: Vector3) -> Vector3:
	var p := get_parent()
	if p != null and p.has_method("_layout_to_scene"):
		return p.call("_layout_to_scene", marker)
	return marker

## Returns the nearest bale within FEED_RADIUS of a feed point, or null.
func _bale_at(pos: Vector3, bales: Array[Node] = []) -> Node3D:
	var best : Node3D = null
	var best_d := FEED_RADIUS
	if bales.is_empty():
		# Fallback for callers that don't pass the per-tick cache (e.g. external
		# callers outside tick()). The cache is empty when no tick has run yet
		# or when the tree is null, so we still need the live group as a backstop.
		if not _bales_cache.is_empty():
			bales = _bales_cache
		else:
			bales = get_tree().get_nodes_in_group("bale")
	for c in bales:
		var cn := c as Node3D
		if cn == null or not cn.has_meta("material_origin"):
			continue
		if not (cn.has_meta("delivered") and bool(cn.get_meta("delivered"))):
			continue   # only vehicle-delivered bales feed the line
		# #9 — a bale CURRENTLY held by a vehicle must never feed, even if it was
		# delivered earlier and then picked back up (it's being hauled away, not
		# sitting at the feed point). BaseVehicle marks the carried bale; the grab
		# is a pure sensor so this meta is the only signal that it's in transit.
		if cn.has_meta("carried") and bool(cn.get_meta("carried")):
			continue
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
	# Honor the caller-supplied container list. Production passes
	# `_waste_containers_cache` (so behaviour is unchanged in-game); direct
	# callers (tests, one-shot dumps before the first tick populates the cache)
	# pass a fresh group query and now actually get their containers searched.
	for c in containers:
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
		_make_connector(a, b)

## #80 — type-aware connector picker. The geometry depends on the SOURCE
## machine (and sometimes its destination): a screw of any kind always
## discharges via a CHUTE per operator rule; everything else falls through to
## the existing gravity-gutter behaviour (only drawn when there's a real >0.4 m
## vertical drop, otherwise no visible connector). Future pairs (blower→cyclone
## ducts, flotation→dewater inclined-screws, etc.) can be added as new
## elif-branches without touching the rest of the chain.
func _make_connector(a: Dictionary, b: Dictionary) -> void:
	var a_world: Vector3 = a["wout"]
	var b_world: Vector3 = b["win"]
	var dir := b_world - a_world
	var length := dir.length()
	if length < 0.05:
		return
	var src_id : String = String(a.get("id", ""))
	var tgt_id : String = String(b.get("id", ""))
	# #106 — BELT → BELT never gets a connector. Two adjacent conveyors meet
	# directly at the discharge roller; the gravity-gutter fallback was drawing
	# an unwanted horizontal bar between them (visible between compactor_belt
	# and compactorband even though they touched). Skip silently.
	if _is_belt_id(src_id) and _is_belt_id(tgt_id):
		return
	# #196 — SHREDDER → BELT: the operator's spec is that the uitvoerband sits
	# DIRECTLY UNDER the shredder discharge (the shredder drops material
	# straight onto the horizontal collector belt). No chute / gutter between
	# them — the belt deck IS the catch surface. Skip the connector.
	if src_id.begins_with("shredder") and _is_belt_id(tgt_id):
		return
	# Rule 1 — SCREW DISCHARGE ALWAYS GETS A CHUTE. Per operator: when material
	# leaves a screw conveyor / dewatering screw / dosing screw, it slides down a
	# chute to whatever the screw is feeding. Auto-fitted between the screw's
	# wout and the target machine's win.
	if _is_screw_source(src_id):
		_spawn_chute(a_world, b_world, 0.32, 0.08, false)
		return
	# Rule 2 — FRICTION SEPARATOR DISCHARGES THROUGH A CLOSED CHUTE. Per
	# operator: the friction_sep throws so much wind + water spray that the
	# downstream connector has to be sealed on top, otherwise the surrounding
	# area gets soaked. Same chute shape as the screw rule but with a lid.
	if _is_friction_sep_source(src_id):
		_spawn_chute(a_world, b_world, 0.34, 0.14, true)
		return
	# Rule 2b — DRYER → BLOWER gets an L-shaped round duct: a forward segment
	# from the dryer's front-bottom discharge, then a 90° lateral turn into
	# the blower inlet. Two parallel dryers each get their own pipe from
	# opposite sides — the V-shape avoids intersection.
	if src_id == "mech_dryer" and tgt_id == "blower":
		_spawn_elbow_duct(a_world, b_world, 0.16)
		return
	# Rule 3 — BLOWER ALWAYS PNEUMATICALLY CONVEYS TO A CYCLONE through a round
	# steel duct. Per operator: blower output → cyclone is deterministic in this
	# plant; the air-laden flake stream runs through a sealed round pipe between
	# the blower discharge and the cyclone tangential inlet.
	if src_id == "blower":
		_spawn_round_duct(a_world, b_world, 0.18)
		return
	# #107 — CYCLONE → BLOWER is the suction-leg of a pneumatic loop (blower
	# pulls air + flake OUT the bottom of the cyclone), same round-pipe geometry
	# as the discharge leg above.
	if src_id == "cyclone" and tgt_id == "blower":
		_spawn_round_duct(a_world, b_world, 0.16)
		return
	# #107 — CYCLONE → SILO (or extruder_silo) is a vertical gravity drop: a
	# tapered funnel from the cyclone's discharge spout into the silo's top
	# inlet. Visualised as a steep narrow chute (closed-top, since cyclone
	# discharge often carries fines that would otherwise drift on air currents).
	if src_id == "cyclone" and (tgt_id == "silo" or tgt_id == "extruder_silo" or tgt_id == "mengsilo" or tgt_id == "doseersilo" or tgt_id == "vss_silo"):
		_spawn_chute(a_world, b_world, 0.30, 0.18, true)
		return
	# #196 — SCHEIDINGSGOOT → FRICTION_SEP: the "glijgoot" slide-chute the
	# operator described. Wide-bottom, open-top, mild slope. Same shape as the
	# screw chute but a wider trough so it visually reads as a real slide
	# instead of a thin gutter. One spawn per sibling fan-out (the macro
	# builder fires this rule once per scheidingsgoot→friction_sep edge).
	if src_id == "scheidingsgoot" and tgt_id == "friction_sep":
		_spawn_chute(a_world, b_world, 0.55, 0.12, false)
		return
	# Otherwise — fall through to the legacy gravity-gutter behaviour.
	_spawn_gravity_gutter(a_world, b_world)

## True when the source id is one of the conveying screws — the cases the
## "screw → anything = chute" rule applies to. Extruder screws live INSIDE the
## extruder unit and don't discharge to the outside, so they're excluded.
static func _is_screw_source(id: String) -> bool:
	return id == "transport_screw" or id == "dewater_screw" or id == "doseerschroef"

## #106 — belt-family check used to suppress the gravity-gutter fallback when
## one conveyor feeds directly into the next (no real gap to bridge). Covers
## the standalone belts (transport / inclined / variable / metal / scraper)
## AND the named intake belts + compactorband + compactor_belt that feed the
## extruder hot end. Add new belt ids to this list as they're built.
static func _is_belt_id(id: String) -> bool:
	if id == "transport_belt" or id == "variable_belt" \
			or id == "inclined_belt_8m" or id == "metal_belt" \
			or id == "compactorband" or id == "compactor_belt" \
			or id == "switch_belt":
		return true
	return id.begins_with("transportband_") or id.begins_with("opzetband") \
			or id.begins_with("westa_band")

## True when the source id is a friction separator — both the dry-process
## frictiescheider and the wet-process frictiewasser kick up enough wind+water
## spray to need a closed-top chute on the discharge.
static func _is_friction_sep_source(id: String) -> bool:
	return id == "friction_sep" or id == "friction_washer" or id == "intensive_washer"

## Spawn a chute from a_world (source out) to b_world (target in). With
## `closed_top = false` it's an open-top trough (floor + 2 side rails); with
## `closed_top = true` it gets a lid on top so wind/water spray (friction
## separators) is contained.
func _spawn_chute(a_world: Vector3, b_world: Vector3, width: float, height: float, closed_top: bool) -> void:
	var dir := b_world - a_world
	var length := dir.length()
	if length < 0.05:
		return
	var mid := (a_world + b_world) * 0.5
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.55, 0.56, 0.58)
	floor_mat.metallic = 0.55
	floor_mat.roughness = 0.45
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.34, 0.34, 0.36)
	rail_mat.metallic = 0.55
	rail_mat.roughness = 0.45
	# Bundle parent — oriented so its local +Z axis points from a_world toward
	# b_world; gives the chute its natural downward tilt where there's a drop.
	var root := Node3D.new()
	_connectors.add_child(root)
	root.global_transform = Transform3D(_basis_along(dir, "z"), mid)
	# Floor trough — sits at the bottom of the chute box.
	var floor_mi := MeshInstance3D.new()
	var fb := BoxMesh.new()
	fb.size = Vector3(width, 0.04, length)
	floor_mi.mesh = fb
	floor_mi.material_override = floor_mat
	floor_mi.position = Vector3(0.0, -height * 0.5, 0.0)
	root.add_child(floor_mi)
	# Two side rails along the length (keep material in the trough).
	for sx in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rb := BoxMesh.new()
		rb.size = Vector3(0.04, height, length)
		rail.mesh = rb
		rail.material_override = rail_mat
		rail.position = Vector3(float(sx) * (width * 0.5 - 0.02), 0.0, 0.0)
		root.add_child(rail)
	# Lid on top — only for closed-top variant (friction separator discharge).
	# Same metal as the floor; sits flush with the top of the side rails.
	if closed_top:
		var lid := MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(width, 0.04, length)
		lid.mesh = lb
		lid.material_override = floor_mat
		lid.position = Vector3(0.0, height * 0.5, 0.0)
		root.add_child(lid)
	# Solid collider so the player can walk on top of the chute without falling
	# through, and so other machines' floor-snap rays see it.
	var col := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(width, height * 1.1, length)
	cs.shape = box
	col.add_child(cs)
	root.add_child(col)

## Round steel duct from a_world to b_world — used for pneumatic conveying
## (currently: blower→cyclone). Single cylinder oriented along the link with a
## small flange at each end so it reads as bolted onto the source + target.
func _spawn_round_duct(a_world: Vector3, b_world: Vector3, radius: float) -> void:
	var dir := b_world - a_world
	var length := dir.length()
	if length < 0.05:
		return
	var mid := (a_world + b_world) * 0.5
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.62, 0.63, 0.66)
	steel_mat.metallic = 0.7
	steel_mat.roughness = 0.35
	var flange_mat := StandardMaterial3D.new()
	flange_mat.albedo_color = Color(0.40, 0.41, 0.44)
	flange_mat.metallic = 0.5
	flange_mat.roughness = 0.45
	var root := Node3D.new()
	_connectors.add_child(root)
	# Cylinder default is along +Y; orient the parent so local +Y points toward b.
	root.global_transform = Transform3D(_basis_along(dir, "y"), mid)
	# Main pipe.
	var pipe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	pipe.mesh = cm
	pipe.material_override = steel_mat
	root.add_child(pipe)
	# Flanges at both ends (slightly proud of the pipe radius).
	for fy in [-length * 0.5 + 0.03, length * 0.5 - 0.03]:
		var fl := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = radius * 1.30
		fm.bottom_radius = radius * 1.30
		fm.height = 0.06
		fl.mesh = fm
		fl.material_override = flange_mat
		fl.position = Vector3(0.0, fy, 0.0)
		root.add_child(fl)
	# Solid collider so the player can't walk through the pipe.
	var col := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var caps := CapsuleShape3D.new()
	caps.radius = radius * 1.05
	caps.height = length
	cs.shape = caps
	col.add_child(cs)
	root.add_child(col)

## #99 — L-shaped round duct from a dryer's front-bottom discharge to the
## blower inlet. Two straight pipe segments meet at a corner: forward from the
## dryer, then lateral into the blower. Each parallel dryer routes its own pipe
## from opposite sides, forming a V that doesn't intersect.
func _spawn_elbow_duct(a_world: Vector3, b_world: Vector3, radius: float) -> void:
	var corner := Vector3(a_world.x, b_world.y, b_world.z)
	var steel_mat := StandardMaterial3D.new()
	steel_mat.albedo_color = Color(0.62, 0.63, 0.66)
	steel_mat.metallic = 0.7
	steel_mat.roughness = 0.35
	var flange_mat := StandardMaterial3D.new()
	flange_mat.albedo_color = Color(0.40, 0.41, 0.44)
	flange_mat.metallic = 0.5
	flange_mat.roughness = 0.45
	var segments : Array[Array] = [[a_world, corner], [corner, b_world]]
	for seg in segments:
		var s0 : Vector3 = seg[0]
		var s1 : Vector3 = seg[1]
		var d := s1 - s0
		var slen := d.length()
		if slen < 0.05:
			continue
		var mid := (s0 + s1) * 0.5
		var root := Node3D.new()
		_connectors.add_child(root)
		root.global_transform = Transform3D(_basis_along(d, "y"), mid)
		var pipe := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = radius
		cm.bottom_radius = radius
		cm.height = slen
		pipe.mesh = cm
		pipe.material_override = steel_mat
		root.add_child(pipe)
		for fy in [-slen * 0.5 + 0.03, slen * 0.5 - 0.03]:
			var fl := MeshInstance3D.new()
			var fm := CylinderMesh.new()
			fm.top_radius = radius * 1.30
			fm.bottom_radius = radius * 1.30
			fm.height = 0.06
			fl.mesh = fm
			fl.material_override = flange_mat
			fl.position = Vector3(0.0, fy, 0.0)
			root.add_child(fl)
		var col := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var caps := CapsuleShape3D.new()
		caps.radius = radius * 1.05
		caps.height = slen
		cs.shape = caps
		col.add_child(cs)
		root.add_child(col)
	# Elbow joint sphere at the corner.
	var elbow := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius * 1.20
	elbow.mesh = sm
	elbow.material_override = flange_mat
	elbow.position = corner
	_connectors.add_child(elbow)

## Legacy: a 0.45 × 0.12 m gravity trough only drawn when the link drops more
## than 0.4 m vertically. Used as the fallback for source machines that don't
## yet have a dedicated connector type defined.
func _spawn_gravity_gutter(a_world: Vector3, b_world: Vector3) -> void:
	var dir := b_world - a_world
	var length := dir.length()
	if length < 0.05:
		return
	var mid := (a_world + b_world) * 0.5
	var drop := a_world.y - b_world.y
	if drop <= 0.4:
		return
	var mat := StandardMaterial3D.new()
	mat.metallic = 0.4
	mat.roughness = 0.5
	mat.albedo_color = Color(0.56, 0.56, 0.60)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.45, 0.12, length)
	mi.mesh = bm
	mi.material_override = mat
	_connectors.add_child(mi)
	mi.global_transform = Transform3D(_basis_along(dir, "z"), mid)
	mi.create_convex_collision()

## Build an orthonormal basis aligned to a world-space direction. Defensively
## returns identity for any degenerate input — without these guards, a
## near-zero or non-finite direction (zero-length link between coincident
## ports, NaN from upstream math) makes .normalized() return NaN, the cross
## products propagate it into every basis column, and the connector node's
## transform sets Inf/NaN every frame for the renderer to scream about.
func _basis_along(axis_world: Vector3, which: String) -> Basis:
	if axis_world.length_squared() < 1e-6 or not axis_world.is_finite():
		return Basis()
	var n := axis_world.normalized()
	var up := Vector3.UP
	if absf(n.dot(up)) > 0.99:
		up = Vector3.RIGHT
	var cross_a := up.cross(n)
	if cross_a.length_squared() < 1e-9:
		return Basis()
	var b := Basis()
	if which == "y":
		var x := cross_a.normalized()
		b.x = x
		b.y = n
		b.z = x.cross(n).normalized()
	else:
		var x2 := cross_a.normalized()
		b.x = x2
		b.y = n.cross(x2).normalized()
		b.z = n
	var out := b.orthonormalized()
	if not (out.x.is_finite() and out.y.is_finite() and out.z.is_finite()):
		return Basis()
	return out

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
