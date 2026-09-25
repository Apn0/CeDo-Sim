extends Node3D
class_name HoseReel

## Controller attached as a child of a wall-mount hose-reel placeable (or a mobile
## HP-washer cart). Owns the BASE ball valve state and dispenses / recovers the
## HoseNozzle the operator carries to the work spot.
##
## E interaction (proximity-gated):
##   • No nozzle deployed → spawn the nozzle in the player's hand
##   • Nozzle already in hand AND player back at the reel → cycle BASE valve
##     (closed → little → lot → closed)
##
## The held HoseNozzle owns the TIP valve; spray rate is min(base, tip).
##
## HP washer reuse: set `nozzle_max_kg_per_s`, `nozzle_range_m`, `nozzle_cone_deg`,
## `nozzle_tint` on the instance to override the defaults. The reel + nozzle code
## is shared (both are just hose tips + valves; the washer is faster and tighter).

@export var nozzle_max_kg_per_s : float = 4.0
@export var nozzle_range_m      : float = 4.0
@export var nozzle_cone_deg     : float = 18.0
@export var nozzle_tint         : Color = Color(0.82, 0.18, 0.16)
@export var prompt_label        : String = "Take hose tip"
## Air mode: deployed nozzle blows RigidBody3D film_scrap instead of scooping
## floor piles. Used by the air-hose hook (no shovel, no water — pure blow).
@export var nozzle_air_mode     : bool = false
@export var nozzle_hose_length_m: float = 10.0

var base_valve_state : int = 0   # 0=closed 1=little 2=lot
var _deployed_nozzle : Node = null
var _player_near     : bool = false
var _player_node     : Node = null

const _NozzleScript := preload("res://src/scenes/world/HoseNozzle.gd")

# =============================================================================
func _ready() -> void:
	add_to_group("hose_reel")
	_build_trigger()

func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "HoseReelTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.4)
	cs.shape = box
	cs.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	_player_node = body
	_refresh_prompt()

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _refresh_prompt() -> void:
	if not _player_near:
		return
	var msg : String
	if _deployed_nozzle == null or not is_instance_valid(_deployed_nozzle):
		msg = "%s  (E)" % prompt_label
	else:
		msg = "Base klep: %s   (E om te wisselen)" % ["DICHT", "WEINIG", "OPEN"][base_valve_state]
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, msg)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	if not event.is_action_pressed("interact"):
		return
	# Don't fight the nozzle's own E-return when the held nozzle is the active
	# inventory slot; the operator is asking to return it, not cycle the base.
	if _deployed_nozzle != null and is_instance_valid(_deployed_nozzle):
		var inv := get_node_or_null("/root/Inventory")
		if inv and bool(inv.call("is_active", _deployed_nozzle)):
			return
	if _deployed_nozzle == null or not is_instance_valid(_deployed_nozzle):
		_deploy_to_player()
	else:
		_cycle_base_valve()
	get_viewport().set_input_as_handled()

func _deploy_to_player() -> void:
	var n = _NozzleScript.new()
	n.max_kg_per_s = nozzle_max_kg_per_s
	n.max_range_m  = nozzle_range_m
	n.cone_half_angle_deg = nozzle_cone_deg
	n.nozzle_tint  = nozzle_tint
	n.air_mode     = nozzle_air_mode
	n.hose_length_m = nozzle_hose_length_m
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(n)
	n.global_position = global_position + Vector3(0.0, 1.0, 0.0)
	_deployed_nozzle = n
	# attach_to_player refuses (and frees the nozzle) when the hotbar is full —
	# clear our ref so we don't think a tip is deployed, and don't strand a freed node.
	if n.has_method("attach_to_player"):
		var ok : bool = bool(n.call("attach_to_player", _player_node, self))
		if not ok:
			_deployed_nozzle = null
		else:
			# Default the base valve to OPEN-LITTLE on a successful deploy so the
			# operator can grab the hose, walk off, and spray with LMB (tip valve)
			# alone — no return trip to crack the base valve first. E at the reel
			# still cycles it (little → lot → closed → little).
			var prev_state := base_valve_state
			base_valve_state = 1
			_valve_sound(prev_state, base_valve_state)
	_refresh_prompt()

func _cycle_base_valve() -> void:
	var prev := base_valve_state
	base_valve_state = (base_valve_state + 1) % 3
	_valve_sound(prev, base_valve_state)
	_refresh_prompt()

## Called by HoseNozzle.return_to_owner() — we close the base valve as a safety
## interlock (you don't leave the reel hot once the tip is back on the cradle).
func on_nozzle_returned(n: Node) -> void:
	if _deployed_nozzle == n:
		_deployed_nozzle.queue_free()
		_deployed_nozzle = null
	var prev := base_valve_state
	base_valve_state = 0
	_valve_sound(prev, base_valve_state)
	_refresh_prompt()

# ── Sound (2026-09-25) ────────────────────────────────────────────────────────
# The operator's "turn-crank old metal manually operated valve" recording:
# src/audio/machine_sounds/hose_reel_valve.tres, event "valve_open" on every
# opening turn (DICHT→WEINIG, WEINIG→OPEN) and "valve_close" on OPEN→DICHT. The
# MachineSound is attached lazily to the PLACED reel body (see _valve_sound)
# and is idempotent, so the first turn creates it and every later turn reuses it.
const _SOUND_BANK := preload("res://src/audio/MachineSoundBank.gd")

func _valve_sound(prev: int, now: int) -> void:
	if prev == now:
		return
	# This controller hangs under the reel's MODEL node; the sound belongs on the
	# PLACED body above it (the ancestor with the placeable_id meta), where
	# LineFlow, tests and the bank all look for it.
	var body : Node = _SOUND_BANK.placed_body_of(get_parent() if get_parent() != null else self)
	var snd : Node = _SOUND_BANK.attach(body, "hose_reel_valve")
	if snd == null:
		return
	snd.call("play_event", "valve_close" if now == 0 else "valve_open")
