extends Node3D

class_name ExtruderMachine

## Scene controller for one extruder. Owns:
##   - the visual mesh (placeholder for now, real EREMA model later)
##   - an interaction Area3D the player can stand inside to trigger inputs
##   - the bound ExtruderModel (pure sim) ticking at 10 Hz via SimTick
##   - debug label so you can SEE state without a HUD yet
##
## Wiring: drag an ExtruderConfig .tres into `config_resource` in the inspector
## (or assign in code). On _ready() the model is constructed + connected to
## SimTick.sim_tick.

@export var config_resource: ExtruderConfig
@export var debug_label_path: NodePath

var model      : ExtruderModel
var _player_in : bool = false
# Pending inputs collected each frame, drained into the next tick.
var _pending   : Dictionary = {}
var _debug_lbl : Label3D

# Cached references to this line's filters. Resolved once after the world
# finishes spawning placeables (deferred). If either reports is_line_down(),
# downstream throughput is zeroed for the tick — melt sits in the barrel
# while the screw keeps turning, which is what the line actually does during
# a filter change.
var _laser_filter : Node = null
var _head_filter  : Node = null

# #223 docs->code — over-pressure trip latches (items 14 + 17). Both trips are
# LATCHING (no chatter): once fired they stay set until the operator resets the
# EMERGENCY_STOP (E key → reset_after_estop), which re-arms them. See the
# OVER-PRESSURE TRIPS section for the two documented shutdowns.
var _upstream_trip_latched : bool = false   # laserfilter 318-bar upstream trip
var _pel_trip_latched      : bool = false   # pelletiser 160-bar MP<PEL interlock
var _lf_trip_connected     : bool = false   # connect upstream_pressure_trip once
# psi->bar for the laser filter's dMP, which LaserFilter keeps in psi
# internally — matches LaserFilter.PSI_PER_BAR. Everything the model carries is bar.
const PSI_PER_BAR : float = 14.5038

# #scada-surfacing — cached ScadaDashboard handle (resolved lazily via group
# "scada_dashboard"). Each tick we push per-line process values + the FAULT
# status string. Throttled to ~5 Hz via _scada_push_t.
var _scada              : Node  = null
var _scada_push_t       : float = 0.0
const SCADA_PUSH_DT_S   : float = 0.2     # 5 Hz refresh — matches LineFlow's cadence

# ── Start button and natraject (operator rulings 2026-09-25, §I1-§I9) ─────────
# The press (E here, _pending["start_production"] from tests and HMIs) is the
# RIGHT white LED ring button. It no longer starts the screw: it hands the
# model's start_seq (ExtruderStartSequence) the state of the natraject, which
# checks it, starts it in order and only then asks the model for the screw.
# This extruder claims its LineFlow node and its natraject nodes, so the line's
# PLC no longer powers them (§I4).
const _SEQ := preload("res://src/sim/ExtruderStartSequence.gd")
## A free-built extruder (not part of a line macro) takes the nearest machine
## of each natraject kind within this reach. No plant number: in the line
## macros the natraject runs from 3.5 m (laserfilter) to ~14 m (weegschaal)
## from the extruder, and a macro extruder takes its own line's machines.
const NATRAJECT_REACH_M : float = 30.0
## How often the natraject is looked up again (a machine placed or deleted).
const NATRAJECT_RESOLVE_S : float = 2.0
var _line_flow : Node = null
var _natraject : Dictionary = {}          # step id -> placed body (Node3D)
var _natraject_resolve_t : float = INF

# =============================================================================
func _ready() -> void:
	if not config_resource:
		push_error("[ExtruderMachine] No ExtruderConfig assigned — defaulting")
		config_resource = ExtruderConfig.new()
	model = ExtruderModel.new(config_resource)
	# Join the discovery group so HmiOverlay's MACHINES screen can find the
	# scene controller for a selected extruder id and bind the 7-zone setpoint
	# panel (ExtruderZonePanel) to its pure ExtruderModel.
	add_to_group("extruder_machine")

	if debug_label_path:
		_debug_lbl = get_node_or_null(debug_label_path) as Label3D

	# Wire up Area3D enter/exit to track whether player can interact
	var area := find_child("InteractionArea", true, false) as Area3D
	if area:
		area.body_entered.connect(_on_body_entered)
		area.body_exited.connect(_on_body_exited)
	else:
		push_warning("[ExtruderMachine] No InteractionArea child found")

	SimTick.sim_tick.connect(_on_sim_tick)
	# #218 — cold spawn: do NOT promote the model to IDLE here. ExtruderModel
	# defaults to State.OFF (see the State enum).
	#
	# CITATION FIX (2026-08-11): this comment used to send the reader to SWI-049
	# "Automaatknop → Voorverwarmen (15 s preheat) → Groene drukknop". SWI-048
	# and SWI-049 are both "Opstarten sorteerlijn" — the SORTING LINE, a
	# different machine. The extruder's own warm-up is Cedo-PROD-SWI-042 p4
	# step 19: starting the 3a/3b compactors "duurt altijd minimaal 30 minuten,
	# in deze opwarm tijd" — at least 30 minutes — and that same step records
	# "Nog SWI maken opstarten extruders", so no extruder start-up SWI exists.
	# That duration now lives in ExtruderConfig.preheat_min_s and is spent in
	# State.PREHEAT; see ExtruderModel._tick_preheat().
	#
	# The barrel is still handed over hot here, because a line at shift change
	# has been running for days. It cools in OFF (_tick_off), and once cold the
	# operator warms it again through PREHEAT instead of being stuck.
	model.melt_temp = config_resource.melt_temp_setpoint
	# Cache the downstream filter refs once the world has spawned. Deferred so
	# placeable nodes that the catalog adds in the same frame as us are present
	# in their groups by the time we look them up.
	call_deferred("_resolve_downstream_filters")
## Find the laser_filter and head_filter that belong to THIS extruder. Nearest
## member of each group wins — fits the standard one-extruder-per-line layout
## without forcing every catalog placeable to carry a line_id meta. Both refs
## stay null if no filter is placed yet; that just means downstream throughput
## isn't gated, which is the previous behaviour.
func _resolve_downstream_filters() -> void:
	_laser_filter = _closest_in_group("laser_filter")
	_head_filter  = _closest_in_group("head_filter")
	# #223 docs->code (item 14) — connect the laserfilter's 318-bar upstream
	# over-pressure trip so it hard-stops the trio (Compactor + extruder +
	# pelletiser). Signal source: LaserFilter.upstream_pressure_trip(bar), fired
	# once when it latches is_tripped. Connected once (guard) because this runs
	# lazily every tick until both filters resolve.
	# doc: docs/plant/swi/laserfilter-smeltdrukverschil__062_CeDo72.md
	if not _lf_trip_connected and _laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_signal("upstream_pressure_trip"):
		_laser_filter.connect("upstream_pressure_trip", _on_upstream_pressure_trip)
		_lf_trip_connected = true

func _closest_in_group(group: String) -> Node:
	if not is_inside_tree():
		return null
	var tree := get_tree()
	if tree == null:
		return null
	var best : Node = null
	var best_d2 : float = INF
	for n in tree.get_nodes_in_group(group):
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d2 : float = (n3.global_position - global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best

# P3 stage A — the catalog body's vacuum pots (VacPot_primary / VacPot_secondary)
# show the model's pot fill, the lid and the gunk. Roots are cached after the
# first find; a body without pots (a bench placeholder) switches the drive off.
var _pot_roots : Dictionary = {}
var _pot_visual_ok : bool = true

func _drive_pot_visual() -> void:
	if model == null or not _pot_visual_ok:
		return
	var body := get_parent() as Node3D
	if body == null:
		_pot_visual_ok = false
		return
	var cap : float = ExtruderModel.VACUUM_POT_CAPACITY_KG
	var gunk_frac : float = model.vacuum_line_gunk_kg / ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG
	var fills := {"primary": model.primary_pot_fill_kg, "secondary": model.secondary_pot_fill_kg}
	for pot_name in fills.keys():
		var kg : float = float(fills[pot_name])
		# The lid is pushed open by the melt once the pot is at capacity — the
		# model's own alarm trigger (ExtruderModel: "vacuum_lid_pushed_open").
		var r : Node3D = PlaceableCatalog.set_vacuum_pot_state(body, String(pot_name), kg / cap,
			kg >= cap, gunk_frac, _pot_roots.get(pot_name, null))
		if r == null:
			_pot_visual_ok = false
			return
		_pot_roots[pot_name] = r

func _process(_delta: float) -> void:
	_drive_pot_visual()
	# Debug visualisation (until diegetic PLC screens land)
	if _debug_lbl and model:
		var status_line := _readable_status()
		var txt := "%s\n[%s]\n%s\nMelt %.0f°C   Screw %.0f rpm\nThroughput %.0f kg/h" % [
			config_resource.display_name,
			model.get_state_name(),
			status_line,
			model.melt_temp,
			model.screw_rpm,
			model.throughput_kg_h,
		]
		# Operator hint — what E does in the current state
		if _player_in:
			txt += "\n\n[E]: %s" % _interact_hint()
		if model.state == ExtruderModel.State.VACUUM_ALARM:
			txt += "\n\n⚠ VACUUM ALARM  %.0fs to cascade ⚠" % model.vacuum_alarm_remaining_s
		_debug_lbl.text = txt

# Plain-English explanation of the current state.
func _readable_status() -> String:
	var seq = model.start_seq
	if seq.alarm != "" or seq.phase == _SEQ.Phase.NATRAJECT_UP or seq.phase == _SEQ.Phase.RUN_DOWN:
		return seq.status_text()
	match model.state:
		ExtruderModel.State.OFF:
			return "Powered off — cold, no rotation."
		ExtruderModel.State.PREHEAT:
			if model.preheat_ready():
				return "Warm-up complete — press the green button to start."
			return "Warming up — %.0f%% (%.0f °C of %.0f °C)." % [
				100.0 * model.preheat_progress(), model.melt_temp,
				config_resource.melt_temp_setpoint]
		ExtruderModel.State.IDLE:
			return "Warm, screw at idle rpm, awaiting feed."
		ExtruderModel.State.STARTING:
			return "Starting — screw ramping up to its %.0f rpm setpoint." % model.screw_rpm_setpoint
		ExtruderModel.State.RUNNING:
			# The rpm setpoint is set per line on the extruder HMI; 60 is the
			# lowest (operator 2026-09-25).
			return "Producing — screw at %.0f rpm (setpoint %.0f, set on the extruder HMI)." % [
				model.screw_rpm, model.screw_rpm_setpoint]
		ExtruderModel.State.VACUUM_ALARM:
			return "Vacuum lost — production continues but cascade clock running."
		ExtruderModel.State.FAULT:
			# New semantics: the line cascade-stops (extruder + vacuums + filters
			# + pelletizer + dewater) while the PCU/compactor keeps running so
			# the donut doesn't seize. No melt runaway / no lump emission.
			return "FAULT — line cascade-stopped (PCU keeps running)."
		ExtruderModel.State.EMERGENCY_STOP:
			return "Emergency stop pulled."
		_:
			return ""

# What the interact key (E) will do in the current state.
func _interact_hint() -> String:
	var seq = model.start_seq
	if seq.alarm != "" and model.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE,
			ExtruderModel.State.PREHEAT, ExtruderModel.State.STOPPING]:
		return "start button dead — %s. Reset the alarm on the extruder HMI" % seq.alarm
	if seq.phase == _SEQ.Phase.NATRAJECT_UP:
		return "start sequence running — %s (ring blinking)" % seq.status_text()
	match model.state:
		ExtruderModel.State.OFF:
			if model.flooded_dismantle_required or model.vacuum_line_gunk_kg >= ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
				return "clean vacuum lines (clear gunk)"
			return "start production" if model.preheat_ready() else "start warm-up"
		ExtruderModel.State.PREHEAT:
			if model.preheat_ready():
				return "start production (barrel at temperature)"
			return "warming up — %.0f%%" % (100.0 * model.preheat_progress())
		ExtruderModel.State.IDLE:
			if model.flooded_dismantle_required or model.vacuum_line_gunk_kg >= ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
				return "clean vacuum lines (clear gunk)"
			return "start production"
		ExtruderModel.State.RUNNING:        return "simulate vacuum loss (test the 120s cascade)"
		ExtruderModel.State.VACUUM_ALARM:
			if not model.pots_below_capacity():
				return "pot %s is full — pull its lid and clean it (at the pot)" % model.vacuum_alarm_pot
			return "restore vacuum (clear alarm)"
		ExtruderModel.State.FAULT:
			if model.flooded_dismantle_required or model.vacuum_line_gunk_kg >= ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
				return "clean vacuum lines & clear fault"
			return "operator-clear fault → back to OFF"
		ExtruderModel.State.EMERGENCY_STOP: return "reset emergency stop (over-pressure trip)"
		_:                                  return ""

# =============================================================================
# SIM TICK (10 Hz, decoupled from frame rate)
# =============================================================================
func _on_sim_tick(delta: float) -> void:
	var inputs := _pending.duplicate()
	_pending.clear()
	_natraject_resolve_t += delta
	if _natraject_resolve_t >= NATRAJECT_RESOLVE_S or _natraject_stale():
		_natraject_resolve_t = 0.0
		_resolve_natraject(_line_flow)
	var nat_status := _natraject_status()
	_route_start_button(inputs, nat_status)
	var seq_out : Dictionary = model.start_seq.tick(delta, nat_status, _screw_driven(),
		model.screw_rpm > 0.5)
	if bool(seq_out["start_screw"]):
		inputs["start_production"] = true
	if String(seq_out["trip"]) != "":
		inputs["natraject_trip"] = String(seq_out["trip"])
		print("[%s] %s — the extruder trips" % [config_resource.line_id, String(seq_out["trip"])])
	# While the natraject comes up the heaters hold the barrel: from OFF the
	# model goes to PREHEAT (it would cool 0.5 °C/s in OFF, and the green
	# threshold is only ~13 °C under the setpoint).
	if model.start_seq.phase == _SEQ.Phase.NATRAJECT_UP \
			and model.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE]:
		inputs["preheat_on"] = true
	var prev_state := model.state
	var events := model.tick(delta, inputs)
	_command_natraject()

	_resolve_lazy_dependencies()
	_update_telemetry(delta)
	_update_downstream_throughput()
	_update_downstream_signals()

	_broadcast(events)

	_check_pressure_trips()
	_handle_state_transitions(prev_state)

## The press of the start button. A cold barrel still goes to its warm-up
## (PREHEAT) without the natraject, as before; a barrel at temperature, or a
## screw still coasting, runs the start sequence. An alarm not yet reset on the
## HMI makes the button dead (rulings §I1: "If you don't reset the alarm, still
## nothing's going to happen"). Anything else keeps the old route: the model
## ignores it.
func _route_start_button(inputs: Dictionary, nat_status: Dictionary) -> void:
	if not bool(inputs.get("start_production", false)):
		return
	inputs.erase("start_production")
	var st := model.state
	var startable : bool = st in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE,
		ExtruderModel.State.PREHEAT, ExtruderModel.State.STOPPING]
	if startable and model.start_seq.alarm != "":
		print("[%s] Start button: nothing happens — %s" % [config_resource.line_id, model.start_seq.alarm])
		return
	if st in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE] and not model.preheat_ready():
		inputs["start_production"] = true   # cold barrel: the model routes it to PREHEAT
		return
	if st == ExtruderModel.State.PREHEAT and not model.preheat_ready():
		return                               # the green button is not live yet
	if startable and not model.start_seq.natraject_enabled:
		# "Natraject" off (the hidden setting): no checks, nothing started, the
		# press goes to the screw exactly as it did before the sequence existed.
		inputs["start_production"] = true
		return
	if startable:
		var why : String = model.start_seq.press(nat_status)
		if why != "":
			print("[%s] Start button: %s" % [config_resource.line_id, why])
		return
	inputs["start_production"] = true

func _screw_driven() -> bool:
	return model.state in [ExtruderModel.State.STARTING, ExtruderModel.State.RUNNING,
		ExtruderModel.State.VACUUM_ALARM]

## The catalog body this brain sits on (MachineBrains.attach adds it as a
## child). It is also the extruder's own LineFlow node. Null on a bench scene.
func _owner_body() -> Node3D:
	var p := get_parent() as Node3D
	if p != null and p.has_meta("placeable_id"):
		return p
	return null

func _natraject_stale() -> bool:
	for b in _natraject.values():
		if b == null or not is_instance_valid(b):
			return true
	return false

## Look up this extruder's natraject in LineFlow and claim it, with the
## extruder's own flow node. A macro-built extruder takes the machines of its
## own build (macro_instance); a free-built one the nearest of each kind within
## NATRAJECT_REACH_M that no macro line and no other extruder holds.
func _resolve_natraject(lf_hint: Node = null) -> void:
	if not is_inside_tree():
		return
	var lf : Node = lf_hint if lf_hint != null and is_instance_valid(lf_hint) 		else get_tree().get_first_node_in_group("line_flow")
	if lf == null or not lf.has_method("flow_bodies"):
		_line_flow = null
		_natraject.clear()
		return
	if _line_flow != null and is_instance_valid(_line_flow) and _line_flow != lf:
		_line_flow.call("release_nodes", self)
	_line_flow = lf
	var me := _owner_body()
	var here : Vector3 = me.global_position if me != null else global_position
	var inst : String = String(me.get_meta("macro_instance")) if me != null and me.has_meta("macro_instance") else ""
	var best : Dictionary = {}
	var best_d : Dictionary = {}
	for e in lf.call("flow_bodies"):
		var id : String = String(e["id"])
		if not _SEQ.STEP_IDS.has(id):
			continue
		var b : Node3D = e["body"]
		var o = lf.call("node_owner", b)
		if o != null and o != self:
			continue
		var d : float = (b.global_position - here).length()
		if inst != "":
			if not b.has_meta("macro_instance") or String(b.get_meta("macro_instance")) != inst:
				continue
		else:
			if b.has_meta("macro_instance") or d > NATRAJECT_REACH_M:
				continue
		if d < float(best_d.get(id, INF)):
			best[id] = b
			best_d[id] = d
	lf.call("release_nodes", self)
	_natraject = best
	for id2 in best:
		lf.call("claim_node", best[id2], self)
	if me != null:
		lf.call("claim_node", me, self)

func _natraject_status() -> Dictionary:
	var st : Dictionary = {}
	for id in _SEQ.STEP_IDS:
		var b = _natraject.get(id, null)
		if _line_flow == null or not is_instance_valid(_line_flow) or b == null or not is_instance_valid(b):
			st[id] = {"found": false, "available": false, "why": "niet gevonden",
				"powered": false, "spin": 0.0}
		else:
			st[id] = _line_flow.call("natraject_status", b)
	return st

## Write the sequence's run commands into LineFlow, and run the extruder's own
## flow node while its screw turns.
func _command_natraject() -> void:
	if _line_flow == null or not is_instance_valid(_line_flow):
		return
	for id in _SEQ.STEP_IDS:
		var b = _natraject.get(id, null)
		if b != null and is_instance_valid(b):
			_line_flow.call("command_node", b, self, bool(model.start_seq.run_cmd.get(id, false)))
	var me := _owner_body()
	if me != null:
		_line_flow.call("command_node", me, self, _screw_driven() or model.screw_rpm > 0.5)

## LineFlow.rebuild() calls this on every extruder so the claims are in place
## before LineFlow's next tick.
func on_line_flow_rebuilt(lf: Node) -> void:
	_natraject_resolve_t = 0.0
	_resolve_natraject(lf)
	_command_natraject()

## The natraject machine bodies this extruder found, by step id (tests, HMI).
func natraject_bodies() -> Dictionary:
	return _natraject.duplicate()

## Resume on load (operator 2026-09-25, rulings file §R1-§R3). PlantResume
## finds this on the placed body ("SimBrain") and saves it with the body's
## factory entry: the model (state, barrel, setpoints, pots, pressures, start
## sequence, pelletiser) and the brain's own two pressure-trip latches.
func save_run_state() -> Dictionary:
	if model == null:
		return {}
	return {
		"model": model.save_run_state(),
		"upstream_trip_latched": _upstream_trip_latched,
		"pel_trip_latched": _pel_trip_latched,
	}

## Called once the load's LineFlow rebuild is done (PlantResume.resume_world),
## which then re-runs on_line_flow_rebuilt so the natraject's run commands reach
## LineFlow before its next tick. The state the model comes back in is announced
## the way a live transition is (_broadcast), so the HMI, SCADA and audio see a
## RUNNING or FAULTED extruder that was never "entered" in this session.
func restore_run_state(d: Dictionary) -> void:
	if model == null or not (d.get("model", null) is Dictionary):
		return
	var missed : Array = model.restore_run_state(d["model"])
	if not missed.is_empty():
		push_warning("[%s] resume: saved fields not on the model: %s" % [config_resource.line_id, str(missed)])
	_upstream_trip_latched = bool(d.get("upstream_trip_latched", false))
	_pel_trip_latched = bool(d.get("pel_trip_latched", false))
	if model.state != ExtruderModel.State.OFF:
		var ev : Array[String] = ["state_changed:%d:%d" % [ExtruderModel.State.OFF, model.state]]
		_broadcast(ev)
	# The over-pressure trip raised its own alarm beside the state change
	# (_trip_shutdown_all_three); a latched one comes back with it.
	if model.state == ExtruderModel.State.EMERGENCY_STOP and (_upstream_trip_latched or _pel_trip_latched):
		EventBus.machine_alarm_raised.emit(config_resource.line_id, "overpressure", 3)
	print("[%s] resumed: %s, melt %.1f °C, screw %.1f rpm (setpoint %.0f)" % [config_resource.line_id,
		model.get_state_name(), model.melt_temp, model.screw_rpm, model.screw_rpm_setpoint])

func _exit_tree() -> void:
	if _line_flow != null and is_instance_valid(_line_flow):
		_line_flow.call("release_nodes", self)

func _resolve_lazy_dependencies() -> void:
	# Lazy fallback in case the filters spawned after our _ready (e.g. when
	# the player places one mid-run). Resolve only if we still have nothing.
	if _laser_filter == null or _head_filter == null:
		_resolve_downstream_filters()
	# Lazy scada resolution — once-only via group lookup, then cached.
	if _scada == null:
		var found := get_tree().get_nodes_in_group("scada_dashboard")
		if not found.is_empty():
			_scada = found[0]

func _update_telemetry(delta: float) -> void:
	_scada_push_t += delta
	if _scada_push_t >= SCADA_PUSH_DT_S and _scada != null and is_instance_valid(_scada) \
			and _scada.has_method("set_param"):
		_scada_push_t = 0.0
		_push_extruder_params_to_scada()

func _update_downstream_throughput() -> void:
	# Downstream filter integration: push the extruder's throughput into each
	# filter so they accumulate debris loading, then gate the EFFECTIVE
	# throughput on whether either filter is mid-change. During a swap or
	# scraper-stop the line is blocked at the die head — screw keeps turning,
	# but no melt is exiting. We zero `throughput_kg_h` after the tick so any
	# downstream consumer (lump output, MachineFlow handoffs, audio) sees the
	# stop without needing to know about filter internals.
	# Only a PRODUCING extruder pushes real melt through the filters. IDLE forwards
	# idle_kg_per_h (50, "screw turning, no feed") which the filter read as real
	# throughput → phantom pressure with the whole line at 0 (operator 2026-07-16).
	# Map OFF/IDLE/FAULT/E-STOP → 0 feed so the LaserFilter no-flow gate parks ΔP.
	var _producing : bool = model.state in [
		ExtruderModel.State.STARTING, ExtruderModel.State.RUNNING,
		ExtruderModel.State.STOPPING, ExtruderModel.State.VACUUM_ALARM]
	var _feed_kg_h : float = model.throughput_kg_h if _producing else 0.0
	if _laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_method("set_feed_throughput"):
		_laser_filter.set_feed_throughput(_feed_kg_h)
	if _head_filter != null and is_instance_valid(_head_filter) \
			and _head_filter.has_method("set_feed_throughput"):
		_head_filter.set_feed_throughput(_feed_kg_h)
	var line_blocked : bool = (_laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_method("is_line_down") and _laser_filter.call("is_line_down")) \
		or (_head_filter != null and is_instance_valid(_head_filter) \
			and _head_filter.has_method("is_line_down") and _head_filter.call("is_line_down"))
	if line_blocked:
		model.throughput_kg_h = 0.0

func _update_downstream_signals() -> void:
	# Operator-confirmed asymmetric clog signals: the laser filter cares about
	# upstream screw RPM (high RPM = more debris-per-second forward), upstream
	# pressure (drives front-face loading bias), and any cold-zone lump
	# passthrough. Forward these every tick while we're producing so the
	# filter's front/back loading model has something live to integrate.
	# All calls are defensive — agent 3 wires the receiving methods on
	# LaserFilter; missing methods just skip silently here.
	if model.state == ExtruderModel.State.RUNNING and _laser_filter != null \
			and is_instance_valid(_laser_filter):
		if _laser_filter.has_method("set_extruder_rpm_indicator"):
			_laser_filter.call("set_extruder_rpm_indicator", model.screw_rpm)
		if _laser_filter.has_method("set_lump_feed_rate") \
				and "lump_passthrough_rate_g_s" in model:
			_laser_filter.call("set_lump_feed_rate", model.lump_passthrough_rate_g_s)
	elif _laser_filter != null and is_instance_valid(_laser_filter):
		# Not producing → clear the amplifier signals at the source, else the last
		# RUNNING values stay latched and keep driving front-face loading + a
		# phantom over-pressure trip with zero flow (operator 2026-07-16).
		if _laser_filter.has_method("set_lump_feed_rate"):
			_laser_filter.call("set_lump_feed_rate", 0.0)
		if _laser_filter.has_method("set_extruder_rpm_indicator"):
			_laser_filter.call("set_extruder_rpm_indicator", 0.0)
	_forward_melt_pressures()

## Melt pressures, bar (2026-09-24). The melt-set pressure after the laser
## filter goes TO the filter (its trip adds its own dMP); the two filter dPs
## come BACK into the model, which derives MP<MF, kopdruk and MP<PEL from them.
## Pressure follows flow, so this uses the producing gate of
## _update_downstream_throughput rather than the RUNNING-only one above: the
## melt still flows in STARTING, STOPPING and VACUUM_ALARM, and the 160-bar
## interlock is armed in all three. The kopfilter's dP is a pack-resistance
## figure that stays put when the flow stops, so it is only mirrored while
## melt moves; the laser filter parks its own dMP at no flow.
func _forward_melt_pressures() -> void:
	var producing : bool = model.state in [
		ExtruderModel.State.STARTING, ExtruderModel.State.RUNNING,
		ExtruderModel.State.STOPPING, ExtruderModel.State.VACUUM_ALARM]
	var laser_ok : bool = _laser_filter != null and is_instance_valid(_laser_filter)
	var head_ok : bool = _head_filter != null and is_instance_valid(_head_filter)
	if laser_ok and _laser_filter.has_method("set_mp_after_filter_bar"):
		_laser_filter.call("set_mp_after_filter_bar",
			model.mp_after_laserfilter_bar if producing else 0.0)
	# The screen's dMP follows the melt's viscosity too (operator 2026-09-25).
	if laser_ok and _laser_filter.has_method("set_melt_viscosity_factor"):
		_laser_filter.call("set_melt_viscosity_factor", model.melt_viscosity_factor)
	var laser_dp : float = 0.0
	if producing and laser_ok and "delta_p_psi" in _laser_filter:
		laser_dp = float(_laser_filter.delta_p_psi) / PSI_PER_BAR
	var kop_dp : float = 0.0
	if producing and head_ok and _head_filter.has_method("delta_p_bar"):
		kop_dp = float(_head_filter.call("delta_p_bar"))
	model.set_filter_pressure_drops(laser_dp, kop_dp)

func _check_pressure_trips() -> void:
	# #223 docs->code (item 17) — pelletiser 160-bar MP<PEL melt-pressure
	# interlock. MP<PEL ("smeltdruk stroomopwaarts van de pelletiseermachine")
	# is, per the operator's ruling of 2026-09-24, the pressure difference ACROSS
	# the kopfilter (MF2), which sits between the melt pump and the heetafslag —
	# the model mirrors it in as mp_pel_bar. Fire the SAME trio shutdown as the
	# 318-bar upstream trip when it exceeds the documented 160-bar limit.
	# Latching; only armed while the extruder is actually pushing melt.
	# doc: docs/plant/swi/EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md
	if not _pel_trip_latched \
			and model.state in [ExtruderModel.State.RUNNING, ExtruderModel.State.STARTING, ExtruderModel.State.VACUUM_ALARM]:
		var mp_pel_bar : float = model.mp_pel_bar
		if mp_pel_bar > EremaFaultRegistry.PEL_MELT_PRESSURE_TRIP_BAR:
			_pel_trip_latched = true
			model.fault_reason = "pelletiser_meltdruk_160bar"
			print("[%s] 160-bar PELLETISER INTERLOCK @ %.0f bar (MP<PEL) — trio shutdown" \
				% [config_resource.line_id, mp_pel_bar])
			_trip_shutdown_all_three("pelletiser_melt_pressure_160bar", mp_pel_bar)
	# #223 docs->code (items 14/17) — keep the over-pressure cause asserted while
	# latched. The model wipes fault_reason to "" on the emergency_stop transition
	# and the melt pressures drop to 0 once stopped, so without this the operator loses
	# the reason the line died. Re-assert it so the SCADA chip + Storingstabel row
	# (EremaFaultRegistry reads fault_reason) persist until the operator resets.
	if model.state == ExtruderModel.State.EMERGENCY_STOP and model.fault_reason == "":
		if _upstream_trip_latched:
			model.fault_reason = "laserfilter_upstream_overpressure_318bar"
		elif _pel_trip_latched:
			model.fault_reason = "pelletiser_meltdruk_160bar"

func _handle_state_transitions(prev_state: int) -> void:
	# Cascade-stop hook: when the 2-min vacuum-alarm grace expires the model
	# transitions to FAULT. Per the operator's anecdote, EVERYTHING downstream
	# halts — screw, both vacuum units, laser filter, head filter, pelletizer,
	# dewater — EXCEPT the PCU/compactor. The PCU continues running so it
	# doesn't seize per the operator anecdote about pot solidification at
	# 125°C; killing it on a cascade-stop would create a worse problem than
	# the one we're recovering from.
	if model.state == ExtruderModel.State.FAULT and prev_state != ExtruderModel.State.FAULT:
		_cascade_stop_downstream()
	# Operator-clear path: when the fault is cleared (FAULT → anything else),
	# resume the laser filter so the line is ready to restart.
	if prev_state == ExtruderModel.State.FAULT and model.state != ExtruderModel.State.FAULT:
		_cascade_resume_downstream()
	# #223 docs->code (items 14/17) — clearing the over-pressure EMERGENCY_STOP
	# (operator reset via E → reset_after_estop) re-arms BOTH trip latches and
	# resumes the frozen downstream filters, mirroring the FAULT-clear resume
	# above. EMERGENCY_STOP is only ever entered by the two over-pressure trips.
	if prev_state == ExtruderModel.State.EMERGENCY_STOP and model.state != ExtruderModel.State.EMERGENCY_STOP:
		_upstream_trip_latched = false
		_pel_trip_latched = false
		# The laser filter latches its own is_tripped; re-arm it too, or the
		# 318-bar trip never fires again after this reset (it signals on the edge).
		if _laser_filter != null and is_instance_valid(_laser_filter) \
				and _laser_filter.has_method("rearm_upstream_trip"):
			_laser_filter.call("rearm_upstream_trip")
		model.fault_reason = ""   # clear the persisted trip cause so the next run is clean
		_cascade_resume_downstream()
	# Feed AudioManager urgency data every tick while the cascade is running
	if model.state == ExtruderModel.State.VACUUM_ALARM:
		EventBus.machine_vacuum_alarm_tick.emit(
			config_resource.line_id, model.vacuum_alarm_remaining_s)
	# State changed → refresh the prompt text (e.g. RUNNING → VACUUM_ALARM)
	if model.state != prev_state and _player_in:
		_emit_prompt()

# Cascade-stop the downstream chain when the extruder faults. Defensive on
# every node — other agents wire the receiving methods, and we must NOT crash
# if any of them haven't landed yet. PCU/compactor is intentionally omitted;
# see the call site for the operator anecdote.
func _cascade_stop_downstream() -> void:
	if _laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_method("cascade_stop"):
		_laser_filter.call("cascade_stop")
	if _head_filter != null and is_instance_valid(_head_filter) \
			and _head_filter.has_method("cascade_stop"):
		_head_filter.call("cascade_stop")
	# SCADA broadcast so audio/HMI/ledger listeners can react. Use the generic
	# scada_event signal if it exists on EventBus, otherwise just log. The
	# emit is wrapped in has_signal so we don't hard-depend on an EventBus
	# revision that hasn't merged yet.
	if EventBus.has_signal("scada_event"):
		EventBus.emit_signal(
			"scada_event",
			config_resource.line_id,
			"cascade_stop_all_except_pcu",
			{})
	else:
		print("[%s] SCADA: cascade_stop_all_except_pcu (no scada_event signal yet)" \
			% config_resource.line_id)

# Counterpart to _cascade_stop_downstream — called when operator_clear_fault
# moves the model out of FAULT. Defensive on every node.
## Per-tick SCADA push for the operator-anecdote telemetry added in the recent
## mechanics pass. Each key is prefixed with the line_id so the dashboard can
## host multiple extruders without collisions ("ex_3A_defect" / "ex_3B_defect"
## etc.). Nominal bands:
##   defect      0..2 % is OK, alarms over 2 %
##   gunk_kg     under 4 kg is OK (= flooded dismantle threshold). Alarms over.
##   mpmf        pressure before the laserfilter, bar. Alarms over 280 — the
##               operator's safe maximum under the 318-bar shutdown (2026-09-24).
##   kopdruk     pressure into the kopfilter, bar. Alarms outside this line's
##               FORM-008 window (config.kopdruk_window_bar).
##   fault       OK if empty; any non-empty fault_reason colours alarm-red.
func _push_extruder_params_to_scada() -> void:
	if _scada == null or not is_instance_valid(_scada):
		return
	var line := config_resource.line_id
	var prefix := "ex_%s_" % line
	if "pellet_defect_rate" in model:
		_scada.call("set_param",
			prefix + "defect",
			model.pellet_defect_rate * 100.0,
			0.0, 2.0,
			"Ex %s Defect  (%%)" % line)
	if "vacuum_line_gunk_kg" in model:
		_scada.call("set_param",
			prefix + "vacgunk",
			model.vacuum_line_gunk_kg,
			0.0, 4.0,
			"Ex %s Vac gunk  (kg)" % line)
	_scada.call("set_param",
		prefix + "mpmf",
		model.mp_before_laserfilter_bar,
		0.0, 280.0,
		"Ex %s MP<MF  (bar)" % line)
	var win : Vector2 = config_resource.kopdruk_window_bar
	_scada.call("set_param",
		prefix + "kopdruk",
		model.kopdruk_bar,
		win.x, win.y,
		"Ex %s Kopdruk  (bar)" % line)
	# Fault reason as a status string. Alarming when non-empty. Uses the
	# dedicated set_text_param branch in the dashboard (grey when "", red
	# when carrying any of the operator-confirmed fault keys).
	if _scada.has_method("set_text_param") and "fault_reason" in model:
		var r : String = String(model.fault_reason)
		_scada.call("set_text_param",
			prefix + "fault",
			r,
			r != "",
			"Ex %s Fault" % line)

func _cascade_resume_downstream() -> void:
	if _laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_method("cascade_resume"):
		_laser_filter.call("cascade_resume")
	if _head_filter != null and is_instance_valid(_head_filter) \
			and _head_filter.has_method("cascade_resume"):
		_head_filter.call("cascade_resume")
	if EventBus.has_signal("scada_event"):
		EventBus.emit_signal(
			"scada_event",
			config_resource.line_id,
			"cascade_resume",
			{})

# =============================================================================
# OVER-PRESSURE TRIPS (docs->code #223, items 14 + 17)
# =============================================================================
# Both the laserfilter 318-bar UPSTREAM trip and the pelletiser 160-bar MP<PEL
# interlock demand the SAME documented action: immediate SIMULTANEOUS shutdown
# of the cutter-compactor/PCU, the extruder itself, AND the pelletiser.
#   - docs/plant/swi/laserfilter-smeltdrukverschil__062_CeDo72.md — upstream
#     melt pressure over the limit → "de Compactor (optie), de extruder en het
#     pelletiseringssysteem onmiddellijk uitgeschakeld".
#   - docs/plant/swi/EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md —
#     MP<PEL > 160 bar → "de Compactor (configureerbaar), de extruder en het
#     pelletiseersysteem onmiddellijk uitgeschakeld".
# This is DELIBERATELY harder than the vacuum-alarm cascade: that one keeps the
# PCU alive (pot-seize anecdote); an over-pressure trip stops the PCU too, per
# both docs. We reuse the existing cascade_stop mechanism (defensive method
# calls on the filters + a SCADA broadcast) rather than inventing a new one.

## Signal handler for LaserFilter.upstream_pressure_trip(bar). Latching (item 14).
func _on_upstream_pressure_trip(bar: float) -> void:
	if _upstream_trip_latched:
		return   # already tripped — no chatter
	_upstream_trip_latched = true
	model.fault_reason = "laserfilter_upstream_overpressure_318bar"
	print("[%s] 318-bar UPSTREAM TRIP @ %.0f bar — shutting down Compactor + extruder + pelletiser" \
		% [config_resource.line_id, bar])
	_trip_shutdown_all_three("laserfilter_upstream_pressure_318bar", bar)

## Shared trio shutdown for BOTH over-pressure trips (items 14 + 17). Mirrors
## _cascade_stop_downstream (defensive filter stops + SCADA broadcast) but also
## commands the PCU/compactor + pelletiser down — the documented full-line trip.
func _trip_shutdown_all_three(reason: String, bar: float) -> void:
	# 1) Extruder itself → immediate hard stop via the model's always-honoured
	# emergency_stop input (screw/throughput/die pressure all zero next tick).
	# Cleared by the operator through reset_after_estop (E key), which re-arms
	# both latches (see the EMERGENCY_STOP resume edge in _on_sim_tick).
	_pending["emergency_stop"] = true
	# 2) Downstream filters → freeze. The laser filter already self-halts on its
	# own is_tripped latch; the head filter is mirrored here for parity.
	if _laser_filter != null and is_instance_valid(_laser_filter) \
			and _laser_filter.has_method("cascade_stop"):
		_laser_filter.call("cascade_stop")
	if _head_filter != null and is_instance_valid(_head_filter) \
			and _head_filter.has_method("cascade_stop"):
		_head_filter.call("cascade_stop")
	# 3) Compactor/PCU + pelletiser → commanded down via the SCADA broadcast.
	# The pelletiser also stops implicitly (the model does not tick it while in
	# EMERGENCY_STOP). Unlike cascade_stop_all_except_pcu, this event carries
	# stop_pcu:true — the documented over-pressure trip stops the compactor too.
	if EventBus.has_signal("scada_event"):
		EventBus.emit_signal(
			"scada_event",
			config_resource.line_id,
			"overpressure_trip_stop_all",
			{"reason": reason, "bar": bar, "stop_pcu": true,
			 "stop_extruder": true, "stop_pelletiser": true})
	# 4) Raise the HMI alarm so the EremaFaultRegistry Storingstabel row is
	# accompanied by a live severity-3 alarm on the panel.
	EventBus.machine_alarm_raised.emit(config_resource.line_id, "overpressure", 3)

func _emit_initial_state() -> void:
	# Broadcast the boot state so AudioManager / HUD start in sync.
	EventBus.machine_state_changed.emit(
		config_resource.line_id,
		ExtruderModel.State.OFF,
		model.state)

func _broadcast(events: Array[String]) -> void:
	for ev in events:
		if ev.begins_with("state_changed:"):
			var parts := ev.split(":")
			var old_s  := parts[1].to_int()
			var new_s  := parts[2].to_int()
			EventBus.machine_state_changed.emit(config_resource.line_id, old_s, new_s)
			# Raise alarms on entry; clear fault alarm on exit from FAULT
			if new_s == ExtruderModel.State.VACUUM_ALARM:
				EventBus.machine_alarm_raised.emit(config_resource.line_id, "vacuum", 2)
			elif new_s == ExtruderModel.State.FAULT:
				EventBus.machine_alarm_raised.emit(config_resource.line_id, "fault", 3)
				# P3 stage B (rulings §14): past the two minutes "a different HMI
				# alarm reports the shutdown due to laser filter error" — the
				# primary pot is the laser filter's, the secondary the head filter's.
				if model.fault_reason == "vacuum_lid_pushed_open":
					if model.vacuum_alarm_pot == "primary" or model.vacuum_alarm_pot == "both":
						EventBus.machine_alarm_raised.emit(config_resource.line_id, "laserfilter_error", 3)
					if model.vacuum_alarm_pot == "secondary" or model.vacuum_alarm_pot == "both":
						EventBus.machine_alarm_raised.emit(config_resource.line_id, "headfilter_error", 3)
			elif old_s == ExtruderModel.State.FAULT:
				EventBus.machine_alarm_cleared.emit(config_resource.line_id, "fault")
				EventBus.machine_alarm_cleared.emit(config_resource.line_id, "laserfilter_error")
				EventBus.machine_alarm_cleared.emit(config_resource.line_id, "headfilter_error")
		elif ev == "fault_lump_produced":
			EventBus.machine_lump_produced.emit(
				config_resource.line_id,
				config_resource.backflush_lump_mass_kg,
				model.melt_temp)
		elif ev == "backflush_triggered":
			EventBus.machine_lump_produced.emit(
				config_resource.line_id,
				config_resource.backflush_lump_mass_kg,
				model.melt_temp)
		elif ev == "vacuum_alarm_cleared":
			EventBus.machine_alarm_cleared.emit(config_resource.line_id, "vacuum")
		elif ev == "vacuum_lines_cleaned":
			EventBus.machine_alarm_cleared.emit(config_resource.line_id, "vacuum_gunk")

## Direct maintenance call: clean vacuum lines and restore 100% degassing capacity.
func clean_vacuum_lines() -> void:
	if model != null:
		model.clean_vacuum_lines()
		print("[%s] Vacuum lines cleaned (capacity restored 100%%)" % (config_resource.line_id if config_resource else "extruder"))

# =============================================================================
# PLAYER INTERACTION — testing harness for the cascade
# =============================================================================
func _on_body_entered(body: Node) -> void:
	if body.name == "Player":
		_player_in = true
		_emit_prompt()

func _on_body_exited(body: Node) -> void:
	if body.name == "Player":
		_player_in = false
		EventBus.interaction_prompt_hide.emit(self)

# Refresh the prompt — call when state changes (so the text follows IDLE→RUNNING→VAC etc.)
func _emit_prompt() -> void:
	if not _player_in:
		return
	var hint := _interact_hint()
	if hint == "":
		EventBus.interaction_prompt_hide.emit(self)
	else:
		EventBus.interaction_prompt_show.emit(self, hint)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_in: return
	# E = trigger vacuum loss (the cascade-test input)
	if event.is_action_pressed("interact"):
		if model.state == ExtruderModel.State.RUNNING:
			_pending["vacuum_lost"] = true
			print("[%s] Operator triggered vacuum loss — 120s grace begins" % config_resource.line_id)
		elif model.state == ExtruderModel.State.VACUUM_ALARM:
			if model.pots_below_capacity():
				_pending["vacuum_restored"] = true
				print("[%s] Operator restored vacuum — alarm cleared" % config_resource.line_id)
			else:
				# P3 stage B: a pushed-open lid is the mini-game at the pot, not
				# a press here (rulings §14).
				print("[%s] Vacuum pot %s is full — its lid stays pushed open until it is cleaned"
					% [config_resource.line_id, model.vacuum_alarm_pot])
		elif model.state == ExtruderModel.State.PREHEAT:
			# The green pushbutton is only live once the display block is green.
			if model.preheat_ready():
				_pending["start_production"] = true
				print("[%s] Operator pressed start (barrel at temperature) — natraject first, then the screw to its %.0f rpm setpoint"
					% [config_resource.line_id, model.screw_rpm_setpoint])
			else:
				print("[%s] Still warming — %.0f%% (%.0f/%.0f °C). The green "
					% [config_resource.line_id, 100.0 * model.preheat_progress(),
					   model.melt_temp, config_resource.melt_temp_setpoint]
					+ "button is not live yet.")
		elif model.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE]:
			if model.flooded_dismantle_required or model.vacuum_line_gunk_kg >= ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
				_pending["clean_vacuum_lines"] = true
				print("[%s] Operator cleaned vacuum lines (clear gunk)" % config_resource.line_id)
			else:
				# On a cold barrel the model routes this to PREHEAT rather than
				# STARTING — see ExtruderModel._route_start_request(). Pressing E on
				# a cold machine used to guarantee a torque trip 2 s later.
				_pending["start_production"] = true
				if model.preheat_ready():
					print("[%s] Operator pressed start — natraject first, then the screw to its %.0f rpm setpoint"
						% [config_resource.line_id, model.screw_rpm_setpoint])
				else:
					print("[%s] Operator started warm-up (barrel cold, %.0f °C)"
						% [config_resource.line_id, model.melt_temp])
		elif model.state == ExtruderModel.State.FAULT:
			if model.flooded_dismantle_required or model.vacuum_line_gunk_kg >= ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
				_pending["clean_vacuum_lines"] = true
				print("[%s] Operator cleaned vacuum lines during fault recovery" % config_resource.line_id)
			_pending["operator_clear_fault"] = true
			print("[%s] Operator cleared fault" % config_resource.line_id)
		elif model.state == ExtruderModel.State.EMERGENCY_STOP:
			# #223 docs->code (items 14/17) — reset the over-pressure trip
			# EMERGENCY_STOP. Re-arm happens on the state edge in _on_sim_tick.
			_pending["reset_after_estop"] = true
			print("[%s] Operator reset emergency stop (over-pressure trip cleared)" % config_resource.line_id)
