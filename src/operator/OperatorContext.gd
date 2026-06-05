extends Node

## Tracks which embodiment the player is currently "in" (on foot, forklift,
## bale clamp, Merlo, scissor lift) and orchestrates switching between them.
##
## NOT an autoload — instanced by MainWorld as a child node, holds references
## to the on-foot CharacterBody3D + the camera, plus the currently-entered
## vehicle (if any).
##
## Architecture rationale: the player has ONE identity (save data, name,
## relationships, scoreboard) but many physical embodiments. The body the
## player controls swaps; everything *about* the player persists across swaps.
##
## Embodiment modes — names used in signals & save data:
##   "on_foot"     — CharacterBody3D + first-person camera
##   "forklift"    — VehicleBody3D, LPG, full fork hydraulics
##   "bale_clamp"  — VehicleBody3D, LPG, vertical clamp plates, no rotation
##   "merlo"       — VehicleBody3D, diesel, telescoping arm + grapple
##   "scissor_lift" — special: platform that rises with player on it

class_name OperatorContext

# ── Configuration (injected by MainWorld) ─────────────────────────────────────
var on_foot_body : CharacterBody3D      # the walking player capsule
var foot_camera  : Camera3D              # camera under Head when on foot

# ── State ─────────────────────────────────────────────────────────────────────
var current_mode    : String = "on_foot"
var current_vehicle : Node3D = null    # null when on_foot
var interactable_vehicle: Node3D = null # vehicle in range to enter (set by VehicleEnterArea)

# =============================================================================
func _ready() -> void:
	# Register in a group so VehicleEnterArea / AudioManager can find us without
	# walking the tree. NEVER use get_tree().root.get_child(0) — autoloads are
	# children of root and push the main scene off index 0 (get_child(0) was
	# silently returning EventBus, which is what broke vehicle entry).
	add_to_group("operator_context")
	# Interact action ("interact" / E) is handled in _unhandled_input below.

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if current_mode == "on_foot":
		# Boarding on foot is owned by PlayerController's crosshair ray; standing
		# inside a VehicleEnterArea only marks that vehicle as reachable.
		return
	elif current_mode != "on_foot" and current_vehicle != null \
			and current_vehicle.has_method("can_exit") and current_vehicle.can_exit():
		_exit_vehicle()

func enter_interactable_vehicle(vehicle: Node3D) -> void:
	if current_mode != "on_foot" or vehicle == null or vehicle != interactable_vehicle:
		return
	if vehicle.has_method("can_enter") and not vehicle.can_enter():
		var reason := ""
		if vehicle.has_method("enter_refusal_reason"):
			reason = String(vehicle.call("enter_refusal_reason"))
		EventBus.interaction_prompt_show.emit(vehicle, reason if reason != "" else "Cannot enter right now")
		return
	_enter_vehicle(vehicle)

# =============================================================================
# ENTER / EXIT
# =============================================================================
func _enter_vehicle(vehicle: Node3D) -> void:
	if not vehicle.has_method("on_operator_entered"):
		push_warning("[OperatorContext] Vehicle missing on_operator_entered(): %s" % vehicle.name)
		return

	var vehicle_type: String = vehicle.get("vehicle_type") if "vehicle_type" in vehicle else "unknown"

	# Two boarding flavours:
	#   CAB ride    (default): hide the player, hand the viewport to the cab camera.
	#   PLATFORM ride (mast lift): KEEP the player visible + active, parent the
	#                              capsule under the lift's platform so it rides
	#                              with it. The operator walks freely on the deck
	#                              while R/F raise and lower the mast under them.
	var is_platform := vehicle.has_method("is_platform_ride") and bool(vehicle.call("is_platform_ride"))
	if is_platform and on_foot_body:
		# Snap the player onto the platform deck and reparent them under it.
		var pnode : Node3D = null
		if vehicle.has_method("platform_node"):
			pnode = vehicle.call("platform_node")
		if pnode != null:
			var deck_pos := pnode.global_position + Vector3(0.0, 1.0, 0.0)
			var world_xf := on_foot_body.global_transform
			world_xf.origin = deck_pos
			if on_foot_body.get_parent():
				on_foot_body.get_parent().remove_child(on_foot_body)
			pnode.add_child(on_foot_body)
			on_foot_body.global_transform = world_xf
			if "velocity" in on_foot_body:
				on_foot_body.velocity = Vector3.ZERO
		# Player keeps its visibility, collision, camera, and physics process.
	elif on_foot_body:
		# Cab path: hide / freeze the on-foot body and hand the camera viewport
		# to the vehicle's cab camera. Without explicit deactivation the player's
		# camera_3d would keep fighting the vehicle's cab camera for who's "current".
		on_foot_body.visible      = false
		on_foot_body.set_physics_process(false)
		on_foot_body.set_process_input(false)
		for child in on_foot_body.get_children():
			if child is CollisionShape3D:
				child.disabled = true
		if on_foot_body.has_method("deactivate_camera"):
			on_foot_body.deactivate_camera()

	# Hand control to the vehicle (it sets occupied=true so R/F + mouse-joystick
	# drive the hydraulics, regardless of which boarding flavour we took).
	vehicle.on_operator_entered(self)

	current_vehicle = vehicle
	var old := current_mode
	current_mode    = vehicle_type
	EventBus.operator_mode_changed.emit(old, current_mode)
	EventBus.operator_entered_vehicle.emit(vehicle)

func _exit_vehicle() -> void:
	if current_vehicle == null:
		return
	var vehicle      := current_vehicle
	var dismount_pos : Vector3 = vehicle.global_position
	if vehicle.has_method("get_dismount_position"):
		dismount_pos = vehicle.get_dismount_position()

	vehicle.on_operator_exited()

	# Restore on-foot body. Two paths again (cab vs platform ride):
	#   PLATFORM: the player capsule was a child of the platform and stayed live
	#             the whole time — just RE-PARENT it back to the world (preserving
	#             world position so they don't snap), then place at dismount.
	#   CAB:      restore visibility / collision / processing and snap to dismount.
	var was_platform := vehicle.has_method("is_platform_ride") and bool(vehicle.call("is_platform_ride"))
	if on_foot_body:
		if was_platform:
			var scene_root := get_tree().current_scene
			var world_xf := on_foot_body.global_transform
			if on_foot_body.get_parent():
				on_foot_body.get_parent().remove_child(on_foot_body)
			scene_root.add_child(on_foot_body)
			on_foot_body.global_transform = world_xf
			# Use the platform's exact current world position as the dismount
			# (the operator can be anywhere on the deck) plus a small forward step.
			on_foot_body.global_position = dismount_pos
		else:
			on_foot_body.global_position = dismount_pos
		if "velocity" in on_foot_body:
			on_foot_body.velocity = Vector3.ZERO
		on_foot_body.visible      = true
		for child in on_foot_body.get_children():
			if child is CollisionShape3D:
				child.disabled = false
		on_foot_body.set_physics_process(true)
		on_foot_body.set_process_input(true)
		# Re-take the viewport — vehicle just deactivated its rig, no camera is
		# current right now. activate_camera() also resets the player rig to
		# first-person so dismount doesn't dump you into orbit mode.
		if on_foot_body.has_method("activate_camera"):
			on_foot_body.activate_camera()

	current_vehicle = null
	var old := current_mode
	current_mode    = "on_foot"
	EventBus.operator_mode_changed.emit(old, current_mode)
	EventBus.operator_exited_vehicle.emit(vehicle)

# =============================================================================
# Range tracking (VehicleEnterArea calls these from its enter/exit signals)
# =============================================================================
func register_interactable(vehicle: Node3D) -> void:
	interactable_vehicle = vehicle

func unregister_interactable(vehicle: Node3D) -> void:
	if interactable_vehicle == vehicle:
		interactable_vehicle = null
