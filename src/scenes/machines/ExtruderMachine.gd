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
# psi->bar for the MP<PEL die-head reading — matches LaserFilter.PSI_PER_BAR.
const PSI_PER_BAR : float = 14.5038

# #scada-surfacing — cached ScadaDashboard handle (resolved lazily via group
# "scada_dashboard"). Each tick we push per-line process values + the FAULT
# status string. Throttled to ~5 Hz via _scada_push_t.
var _scada              : Node  = null
var _scada_push_t       : float = 0.0
const SCADA_PUSH_DT_S   : float = 0.2     # 5 Hz refresh — matches LineFlow's cadence

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

func _process(_delta: float) -> void:
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
		ExtruderModel.State.RUNNING:
			return "Producing — feed flowing, screw at production rpm."
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
	match model.state:
		ExtruderModel.State.OFF:
			return "start production" if model.preheat_ready() else "start warm-up"
		ExtruderModel.State.PREHEAT:
			if model.preheat_ready():
				return "start production (barrel at temperature)"
			return "warming up — %.0f%%" % (100.0 * model.preheat_progress())
		ExtruderModel.State.IDLE:           return "start production"
		ExtruderModel.State.RUNNING:        return "simulate vacuum loss (test the 120s cascade)"
		ExtruderModel.State.VACUUM_ALARM:   return "restore vacuum (clear alarm)"
		ExtruderModel.State.FAULT:          return "operator-clear fault → back to OFF"
		ExtruderModel.State.EMERGENCY_STOP: return "reset emergency stop (over-pressure trip)"
		_:                                  return ""

# =============================================================================
# SIM TICK (10 Hz, decoupled from frame rate)
# =============================================================================
func _on_sim_tick(delta: float) -> void:
	var inputs := _pending.duplicate()
	_pending.clear()
	var prev_state := model.state
	var events := model.tick(delta, inputs)
	# Lazy fallback in case the filters spawned after our _ready (e.g. when
	# the player places one mid-run). Resolve only if we still have nothing.
	if _laser_filter == null or _head_filter == null:
		_resolve_downstream_filters()
	# Lazy scada resolution — once-only via group lookup, then cached.
	if _scada == null:
		var found := get_tree().get_nodes_in_group("scada_dashboard")
		if not found.is_empty():
			_scada = found[0]
	_scada_push_t += delta
	if _scada_push_t >= SCADA_PUSH_DT_S and _scada != null and is_instance_valid(_scada) \
			and _scada.has_method("set_param"):
		_scada_push_t = 0.0
		_push_extruder_params_to_scada()
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
		if _laser_filter.has_method("set_upstream_pressure_indicator"):
			# Real upstream pressure: prefer the head filter's live ΔP (it's
			# physically the laser filter's immediate upstream and is already
			# psi-scale) — falls back to the model's die_pressure_psi (rheology-
			# derived from throughput × viscosity) if no head filter is cached.
			# Both surfaces are psi and on the same scale the operator HMI uses.
			var upstream_psi : float = 0.0
			if _head_filter != null and is_instance_valid(_head_filter) \
					and _head_filter.has_method("delta_p_psi"):
				upstream_psi = float(_head_filter.call("delta_p_psi"))
			if upstream_psi <= 0.0 and "die_pressure_psi" in model:
				upstream_psi = model.die_pressure_psi
			_laser_filter.call("set_upstream_pressure_indicator", upstream_psi)
		if _laser_filter.has_method("set_lump_feed_rate") \
				and "lump_passthrough_rate_g_s" in model:
			_laser_filter.call("set_lump_feed_rate", model.lump_passthrough_rate_g_s)
	elif _laser_filter != null and is_instance_valid(_laser_filter):
		# Not producing → clear the amplifier signals at the source, else the last
		# RUNNING values stay latched and keep driving front-face loading + a
		# phantom over-pressure trip with zero flow (operator 2026-07-16).
		if _laser_filter.has_method("set_lump_feed_rate"):
			_laser_filter.call("set_lump_feed_rate", 0.0)
		if _laser_filter.has_method("set_upstream_pressure_indicator"):
			_laser_filter.call("set_upstream_pressure_indicator", 0.0)
		if _laser_filter.has_method("set_extruder_rpm_indicator"):
			_laser_filter.call("set_extruder_rpm_indicator", 0.0)
	_broadcast(events)
	# #223 docs->code (item 17) — pelletiser 160-bar MP<PEL melt-pressure
	# interlock. Read the die-head / meltpump-outlet melt pressure the model
	# computes (die_pressure_psi = "smeltdruk stroomopwaarts van de
	# pelletiseermachine"), convert to bar, and fire the SAME trio shutdown as the
	# 318-bar upstream trip when it exceeds the documented 160-bar limit. Latching;
	# only armed while the extruder is actually pushing melt.
	# doc: docs/plant/swi/EREMA-manual-4.3.7-pelletiseersysteem__169_CeDo84.md
	if not _pel_trip_latched and "die_pressure_psi" in model \
			and model.state in [ExtruderModel.State.RUNNING, ExtruderModel.State.STARTING, ExtruderModel.State.VACUUM_ALARM]:
		var mp_pel_bar : float = model.die_pressure_psi / PSI_PER_BAR
		if mp_pel_bar > EremaFaultRegistry.PEL_MELT_PRESSURE_TRIP_BAR:
			_pel_trip_latched = true
			model.fault_reason = "pelletiser_meltdruk_160bar"
			print("[%s] 160-bar PELLETISER INTERLOCK @ %.0f bar (MP<PEL) — trio shutdown" \
				% [config_resource.line_id, mp_pel_bar])
			_trip_shutdown_all_three("pelletiser_melt_pressure_160bar", mp_pel_bar)
	# #223 docs->code (items 14/17) — keep the over-pressure cause asserted while
	# latched. The model wipes fault_reason to "" on the emergency_stop transition
	# and die_pressure drops to 0 once stopped, so without this the operator loses
	# the reason the line died. Re-assert it so the SCADA chip + Storingstabel row
	# (EremaFaultRegistry reads fault_reason) persist until the operator resets.
	if model.state == ExtruderModel.State.EMERGENCY_STOP and model.fault_reason == "":
		if _upstream_trip_latched:
			model.fault_reason = "laserfilter_upstream_overpressure_318bar"
		elif _pel_trip_latched:
			model.fault_reason = "pelletiser_meltdruk_160bar"
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
##   die_psi     200..420 psi is the operating envelope. Alarms outside.
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
	if "die_pressure_psi" in model:
		_scada.call("set_param",
			prefix + "diepsi",
			model.die_pressure_psi,
			200.0, 420.0,
			"Ex %s Die  (psi)" % line)
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
			elif old_s == ExtruderModel.State.FAULT:
				EventBus.machine_alarm_cleared.emit(config_resource.line_id, "fault")
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
			_pending["vacuum_restored"] = true
			print("[%s] Operator restored vacuum — alarm cleared" % config_resource.line_id)
		elif model.state == ExtruderModel.State.PREHEAT:
			# The green pushbutton is only live once the display block is green.
			if model.preheat_ready():
				_pending["start_production"] = true
				print("[%s] Operator started production (barrel at temperature)"
					% config_resource.line_id)
			else:
				print("[%s] Still warming — %.0f%% (%.0f/%.0f °C). The green "
					% [config_resource.line_id, 100.0 * model.preheat_progress(),
					   model.melt_temp, config_resource.melt_temp_setpoint]
					+ "button is not live yet.")
		elif model.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE]:
			# On a cold barrel the model routes this to PREHEAT rather than
			# STARTING — see ExtruderModel._route_start_request(). Pressing E on
			# a cold machine used to guarantee a torque trip 2 s later.
			_pending["start_production"] = true
			if model.preheat_ready():
				print("[%s] Operator started production" % config_resource.line_id)
			else:
				print("[%s] Operator started warm-up (barrel cold, %.0f °C)"
					% [config_resource.line_id, model.melt_temp])
		elif model.state == ExtruderModel.State.FAULT:
			_pending["operator_clear_fault"] = true
			print("[%s] Operator cleared fault" % config_resource.line_id)
		elif model.state == ExtruderModel.State.EMERGENCY_STOP:
			# #223 docs->code (items 14/17) — reset the over-pressure trip
			# EMERGENCY_STOP. Re-arm happens on the state edge in _on_sim_tick.
			_pending["reset_after_estop"] = true
			print("[%s] Operator reset emergency stop (over-pressure trip cleared)" % config_resource.line_id)
