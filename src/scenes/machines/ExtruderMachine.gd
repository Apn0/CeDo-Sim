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

# =============================================================================
func _ready() -> void:
	if not config_resource:
		push_error("[ExtruderMachine] No ExtruderConfig assigned — defaulting")
		config_resource = ExtruderConfig.new()
	model = ExtruderModel.new(config_resource)

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
	# Boot to IDLE so MainWorld doesn't have to send a START command
	model.state = ExtruderModel.State.IDLE
	model.melt_temp = config_resource.melt_temp_setpoint
	# Deferred emit so AudioManager + HUD are guaranteed to be connected first
	call_deferred("_emit_initial_state")

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
		ExtruderModel.State.IDLE:
			return "Warm, screw at idle rpm, awaiting feed."
		ExtruderModel.State.RUNNING:
			return "Producing — feed flowing, screw at production rpm."
		ExtruderModel.State.VACUUM_ALARM:
			return "Vacuum lost — production continues but cascade clock running."
		ExtruderModel.State.FAULT:
			return "FAULT — melt runaway, lumps extruding catastrophically."
		ExtruderModel.State.EMERGENCY_STOP:
			return "Emergency stop pulled."
		_:
			return ""

# What the interact key (E) will do in the current state.
func _interact_hint() -> String:
	match model.state:
		ExtruderModel.State.IDLE:           return "start production"
		ExtruderModel.State.RUNNING:        return "simulate vacuum loss (test the 120s cascade)"
		ExtruderModel.State.VACUUM_ALARM:   return "restore vacuum (clear alarm)"
		ExtruderModel.State.FAULT:          return "operator-clear fault → back to OFF"
		_:                                  return ""

# =============================================================================
# SIM TICK (10 Hz, decoupled from frame rate)
# =============================================================================
func _on_sim_tick(delta: float) -> void:
	var inputs := _pending.duplicate()
	_pending.clear()
	var prev_state := model.state
	var events := model.tick(delta, inputs)
	_broadcast(events)
	# Feed AudioManager urgency data every tick while the cascade is running
	if model.state == ExtruderModel.State.VACUUM_ALARM:
		EventBus.machine_vacuum_alarm_tick.emit(
			config_resource.line_id, model.vacuum_alarm_remaining_s)
	# State changed → refresh the prompt text (e.g. RUNNING → VACUUM_ALARM)
	if model.state != prev_state and _player_in:
		_emit_prompt()

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
		elif model.state == ExtruderModel.State.IDLE:
			_pending["start_production"] = true
			print("[%s] Operator started production" % config_resource.line_id)
		elif model.state == ExtruderModel.State.FAULT:
			_pending["operator_clear_fault"] = true
			print("[%s] Operator cleared fault" % config_resource.line_id)
