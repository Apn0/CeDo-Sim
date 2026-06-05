extends StaticBody3D
class_name ServiceStation

## A refuelling / recharging point on the lot. Two modes:
##   • "outlet" — a wall power outlet that recharges an ELECTRIC machine's drive
##                battery (the JLG mast lift). Park the lift next to it, hop out,
##                press E to plug in; it charges over time. E again / driving off
##                unplugs.
##   • "pump"   — a diesel bowser that refills the FUEL tank (diesel + LPG) and
##                tops the AdBlue/DEF on diesel machines.
##
## The player operates it ON FOOT (they've stepped out of the cab). On interact we
## connect to the nearest matching parked vehicle within CONNECT_RANGE and service
## it each frame until full or it leaves range. Pure-logic methods (connect/tick)
## make it headless-testable; the proximity prompt + model are cosmetic.

signal service_changed   # connection/level changed — for a HUD ping

@export_enum("outlet", "pump") var mode : String = "outlet"
@export var connect_range : float = 6.0

# Service rates (per second). Outlet charges the 0..1 battery; pump fills litres.
const CHARGE_PER_S : float = 1.0 / 90.0    # ~90 s to fully charge at the outlet (game-fast)
const FUEL_PER_S   : float = 6.0           # litres/s
const ADBLUE_PER_S : float = 1.2           # litres/s

var _connected : Node = null     # the vehicle currently being serviced
var _player_near : bool = false

# Outlet stations spawn a physical ChargingPlug — operator has to physically
# pick it up and push it into a vehicle's ChargePort. Pumps still use the
# legacy proximity-only flow (E near pump = refuel) — diesel hoses are not
# in scope yet.
const ChargingPlugScript = preload("res://src/scenes/world/ChargingPlug.gd")
var plug : Node3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("service_station")
	_build_trigger()
	if mode == "outlet":
		_spawn_plug()

func _process(delta: float) -> void:
	if _connected == null:
		return
	if not is_instance_valid(_connected) or _vehicle_out_of_range(_connected):
		disconnect_vehicle()
		return
	var still := _tick_service(_connected, delta)
	if not still:
		# Topped off — leave it connected (idle) but ping once.
		emit_signal("service_changed")

## Service one frame. Returns true while there's still something to fill/charge.
func _tick_service(v: Node, delta: float) -> bool:
	if mode == "outlet":
		if String(v.get("fuel_type")) != "electric":
			return false
		return bool(v.call("recharge", CHARGE_PER_S * delta))
	else:
		var more := false
		more = bool(v.call("refuel", FUEL_PER_S * delta)) or more
		if String(v.get("fuel_type")) == "diesel":
			more = bool(v.call("refill_adblue", ADBLUE_PER_S * delta)) or more
		return more

# =============================================================================
# CONNECT / DISCONNECT (the headless-test surface)
# =============================================================================
## Plug into the nearest compatible parked vehicle within range. Returns it (or
## null if nothing suitable). "outlet" only takes electric machines; "pump" only
## combustion (diesel / lpg).
func connect_nearest() -> Node:
	var best : Node = null
	var best_d := connect_range
	for v in _vehicles():
		if not _compatible(v):
			continue
		var d := (v as Node3D).global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = v
	_connected = best
	emit_signal("service_changed")
	return best

func disconnect_vehicle() -> void:
	_connected = null
	emit_signal("service_changed")

func is_connected_to_vehicle() -> bool:
	return _connected != null and is_instance_valid(_connected)

func connected_vehicle() -> Node:
	return _connected

func _compatible(v: Node) -> bool:
	var ft := String(v.get("fuel_type"))
	if mode == "outlet":
		return ft == "electric"
	# LPG was previously refilled at the pump too — that's gone now that the
	# physical cylinder swap (LPGTank + LPGRack) is in. Diesel keeps the pump.
	return ft == "diesel"

func _vehicle_out_of_range(v: Node) -> bool:
	return (v as Node3D).global_position.distance_to(global_position) > connect_range + 1.0

func _vehicles() -> Array:
	var out : Array = []
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return out
	var scene := (ml as SceneTree).current_scene
	if scene == null:
		return out
	for c in scene.get_children():
		if c is BaseVehicle:
			out.append(c)
	return out

# =============================================================================
# PROXIMITY PROMPT + interact (player on foot)
# =============================================================================
func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "ServiceTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.4, 2.6)
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
	var label := "Plug in nearest lift" if mode == "outlet" else "Refuel nearest machine"
	_emit_prompt_show(label)

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_emit_prompt_hide()

func _unhandled_input(event: InputEvent) -> void:
	# Outlet flow is now physicalised: the plug owns the E interaction. The
	# station only handles E for non-outlet modes (pump / future hoses).
	if mode == "outlet":
		return
	if not _player_near:
		return
	if event.is_action_pressed("interact"):
		if is_connected_to_vehicle():
			disconnect_vehicle()
		else:
			connect_nearest()
		get_viewport().set_input_as_handled()

# =============================================================================
# PHYSICALISED PLUG (outlet mode)
# =============================================================================
## Called by ChargingPlug._plug_into() when the operator pushes the plug into
## a vehicle's ChargePort. The station then drives `recharge()` per-frame
## through its existing _tick_service() loop.
func attach_plug_to_vehicle(v: Node) -> void:
	_connected = v
	emit_signal("service_changed")

func _spawn_plug() -> void:
	# Socket anchor: a Node3D 1.0 m up on the +X face of the station (so the
	# plug clearly hangs off a wall socket rather than the centre of the box).
	var anchor := Node3D.new()
	anchor.name = "SocketAnchor"
	anchor.transform = Transform3D(Basis(), Vector3(0.35, 1.0, 0.0))
	add_child(anchor)
	plug = ChargingPlugScript.new()
	plug.name = "Plug"
	plug.station = self
	plug.socket_anchor = anchor
	# Spawn the plug AT WORLD ROOT so its cable visual (which lives in scene
	# space) can be drawn independent of the station's transform. We park it
	# in front of the anchor as the initial "socketed" pose.
	call_deferred("_install_plug_into_world", anchor)

func _install_plug_into_world(anchor: Node3D) -> void:
	var root := get_tree().current_scene
	if root == null:
		return
	root.add_child(plug)
	plug.global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)),
		anchor.global_position + Vector3(0.05, 0.0, 0.0))

func _emit_prompt_show(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
