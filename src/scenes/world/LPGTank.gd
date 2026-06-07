extends StaticBody3D
class_name LPGTank

## Physical LPG (propane) cylinder. Forklifts carry ONE on the counterweight;
## BaleClamps carry TWO and can switch which one feeds the engine. When the
## active tank runs dry, the operator hops out, walks to the outdoor LPGRack,
## peels off a full one, walks back, and clicks it onto the mount.
##
## `level` ∈ [0..1] is the canonical fill state. While mounted, the vehicle
## syncs its `fuel_l` to `level * fuel_capacity_l` each frame so the existing
## fuel-burn loop in BaseVehicle keeps working unchanged. When unmounted, the
## tank is a holdable item — same E-pickup flow as the scissors/scanner, but
## carried in a dedicated "tank in hand" slot (NOT the 4-slot Inventory: the
## operator's arms are full carrying a 20 kg cylinder, so they can't also be
## holding a barcode scanner). State machine:
##
##   FREE          — on the rack / on the floor / dropped from a vehicle
##   HELD          — carried by the player (parented under their Head)
##   MOUNTED       — attached to a vehicle's LPG_Mount* anchor
##
## tool_id is exposed so the player_held_object debug UI can label it, but
## taking an LPGTank does NOT go through the Inventory autoload because it's
## "two hands on the tank" — operator can't swap to scissors mid-carry.

const tool_id : String = "lpg_tank"

# Visual look
const TANK_DIAMETER : float = 0.34
const TANK_HEIGHT   : float = 0.62
const PICKUP_RANGE  : float = 1.3

enum State { FREE, HELD, MOUNTED }
var state : int = State.FREE

# 0 = empty, 1 = full. Bums up against vehicle.fuel_consumption_l_per_h when
# mounted; updated by LPGRack initial spawn.
@export var level : float = 1.0

# Refs / scratch
var _held_by      : Node3D = null
var _mount_anchor : Node3D = null      # Node3D under a vehicle when MOUNTED
var _mount_vehicle: Node   = null      # the BaseVehicle that owns the mount
var _player_near  : bool   = false
var _player_node  : Node   = null

# Visual handles for the fill-band tint update
var _band_mesh    : MeshInstance3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("lpg_tank")
	_build_visual()
	_build_pickup_trigger()
	_apply_level_tint()

func _build_visual() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.18, 0.14); red.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12); dark.roughness = 0.85
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.74, 0.62, 0.20); brass.metallic = 0.85; brass.roughness = 0.25
	# Cylinder body
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := CylinderMesh.new()
	bm.top_radius = TANK_DIAMETER * 0.5
	bm.bottom_radius = TANK_DIAMETER * 0.5
	bm.height = TANK_HEIGHT * 0.85
	bm.radial_segments = 22
	body.mesh = bm
	body.material_override = red
	body.position = Vector3(0, TANK_HEIGHT * 0.5, 0)
	add_child(body)
	# Domed top
	var dome := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = TANK_DIAMETER * 0.5
	dm.height = TANK_DIAMETER * 0.45
	dm.radial_segments = 22
	dome.mesh = dm
	dome.material_override = red
	dome.position = Vector3(0, TANK_HEIGHT * 0.925, 0)
	add_child(dome)
	# Base ring (stand)
	var ring := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = TANK_DIAMETER * 0.55
	rm.bottom_radius = TANK_DIAMETER * 0.58
	rm.height = 0.04
	rm.radial_segments = 22
	ring.mesh = rm
	ring.material_override = dark
	ring.position = Vector3(0, 0.04, 0)
	add_child(ring)
	# Valve neck
	var valve := MeshInstance3D.new()
	var vm := CylinderMesh.new()
	vm.top_radius = 0.04
	vm.bottom_radius = 0.05
	vm.height = 0.10
	vm.radial_segments = 12
	valve.mesh = vm
	valve.material_override = brass
	valve.position = Vector3(0, TANK_HEIGHT + 0.05, 0)
	add_child(valve)
	# Fill-band — a thin coloured ring around the body whose colour reflects
	# the current level (green = full, amber = mid, red = low). Provides an
	# at-a-glance gauge for the operator without needing a UI.
	_band_mesh = MeshInstance3D.new()
	_band_mesh.name = "FillBand"
	var bbm := CylinderMesh.new()
	bbm.top_radius = TANK_DIAMETER * 0.51
	bbm.bottom_radius = TANK_DIAMETER * 0.51
	bbm.height = 0.05
	bbm.radial_segments = 22
	_band_mesh.mesh = bbm
	_band_mesh.material_override = StandardMaterial3D.new()
	_band_mesh.position = Vector3(0, TANK_HEIGHT * 0.18, 0)
	add_child(_band_mesh)
	# Collision (capsule-ish — single cylinder shape)
	var col := CollisionShape3D.new()
	var cs := CylinderShape3D.new()
	cs.radius = TANK_DIAMETER * 0.5
	cs.height = TANK_HEIGHT
	col.shape = cs
	col.position = Vector3(0, TANK_HEIGHT * 0.5, 0)
	add_child(col)

func _build_pickup_trigger() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = PICKUP_RANGE
	cs.shape = sp
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _apply_level_tint() -> void:
	if _band_mesh == null:
		return
	var m := _band_mesh.material_override as StandardMaterial3D
	if m == null:
		return
	# Lerp green → amber → red as level drops 1 → 0.5 → 0.
	var c : Color
	if level >= 0.5:
		var t := (level - 0.5) * 2.0
		c = Color(0.25, 0.70, 0.32, 1).lerp(Color(0.95, 0.78, 0.20, 1), 1.0 - t)
	else:
		var t := level * 2.0
		c = Color(0.95, 0.78, 0.20, 1).lerp(Color(0.80, 0.16, 0.10, 1), 1.0 - t)
	m.albedo_color = c
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.3

func set_level(new_level: float) -> void:
	level = clampf(new_level, 0.0, 1.0)
	_apply_level_tint()

# =============================================================================
# INTERACTION
# =============================================================================
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
	_emit_prompt_hide()

func _refresh_prompt() -> void:
	if not _player_near:
		_emit_prompt_hide(); return
	match state:
		State.FREE:
			_emit_prompt("Take LPG cylinder  (%d %%)" % int(round(level * 100.0)))
		State.HELD:
			pass  # no prompt; operator already holding it
		State.MOUNTED:
			_emit_prompt("Remove LPG cylinder  (%d %%)" % int(round(level * 100.0)))

func _unhandled_input(event: InputEvent) -> void:
	# Q (hotbar_drop) — drop a held tank straight to the floor.
	if event.is_action_pressed("hotbar_drop") and state == State.HELD:
		_drop_to_floor()
		get_viewport().set_input_as_handled()
		return
	# G (tool_place_mode) — place a held tank: snap to a vehicle mount if one is in
	# range, otherwise drop to the floor (so G is a useful single action either way).
	if event.is_action_pressed("tool_place_mode") and state == State.HELD:
		var mount_g := _find_vehicle_mount()
		if not mount_g.is_empty():
			_mount_to(mount_g.get("anchor"), mount_g.get("vehicle"))
		else:
			_drop_to_floor()
		get_viewport().set_input_as_handled()
		return
	if not event.is_action_pressed("interact"):
		return
	match state:
		State.FREE:
			if _player_near:
				_pick_up(_player_node)
				get_viewport().set_input_as_handled()
		State.HELD:
			# Held → check for a vehicle LPG mount within range. If one is
			# found, snap to it. Otherwise drop on the floor in front of you.
			var mount := _find_vehicle_mount()
			if not mount.is_empty():
				_mount_to(mount.get("anchor"), mount.get("vehicle"))
			else:
				_drop_to_floor()
			get_viewport().set_input_as_handled()
		State.MOUNTED:
			# Cylinder changes are an ON-FOOT job (#LPG-cab-lock): refuse the swap
			# when the operator is sitting in a vehicle. Real plants treat this as a
			# tag-out: leave the cab, change the bottle, climb back in.
			if _player_near and not _operator_in_vehicle():
				_remove_from_mount(_player_node)
				get_viewport().set_input_as_handled()

## True when the operator (player) is currently seated in any vehicle. Used to block
## LPG-cylinder swaps from the cab — that's an on-foot job per the operator.
func _operator_in_vehicle() -> bool:
	var scene := get_tree().current_scene
	if scene == null:
		return false
	var oc := scene.find_child("OperatorContext", true, false)
	return oc != null and oc.get("current_vehicle") != null

# =============================================================================
# PICK UP / DROP / MOUNT
# =============================================================================
## True if `player` is already carrying an LPG cylinder. They have two hands and
## a 20 kg bottle — one at a time, max (operator: "should only be one maximum").
static func player_holds_tank(player: Node) -> bool:
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return false
	for t in (ml as SceneTree).get_nodes_in_group("lpg_tank"):
		if int(t.get("state")) == State.HELD and t.get("_held_by") == player:
			return true
	return false

func _pick_up(player: Node3D) -> void:
	# One cylinder at a time.
	if player_holds_tank(player):
		_emit_prompt("Hands full — set the other cylinder down first")
		return
	_held_by = player
	if get_parent():
		get_parent().remove_child(self)
	var head := player.get_node_or_null("Head") as Node3D
	(head if head else player).add_child(self)
	# Held pose: both-hands carry in front of the chest. Tank stands upright
	# (LPG cylinders should never be carried sideways IRL).
	transform = Transform3D(Basis(), Vector3(0.0, -0.55, -0.55))
	collision_layer = 0
	collision_mask  = 0
	state = State.HELD
	_emit_prompt_hide()

func _drop_to_floor() -> void:
	if _held_by == null:
		return
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.7, -0.8)
	if get_parent():
		get_parent().remove_child(self)
	scene_root.add_child(self)
	global_transform = Transform3D(Basis(), drop_world)
	collision_layer = 1
	collision_mask  = 1
	state = State.FREE
	_held_by = null
	visible = true

func _mount_to(anchor: Node3D, vehicle: Node) -> void:
	if anchor == null or vehicle == null:
		return
	# If the mount already holds a DIFFERENT tank, EJECT it to the floor first so the
	# operator swaps in ONE action: walk up holding a fresh bottle, press E → the empty
	# pops off + the fresh one snaps on (no more set-down / pull / carry / re-grab). #14
	if anchor.has_meta("mounted_tank") and anchor.get_meta("mounted_tank") != null:
		var existing : Node = anchor.get_meta("mounted_tank")
		if is_instance_valid(existing) and existing != self and existing.has_method("eject_to_floor"):
			existing.call("eject_to_floor")
	if get_parent():
		get_parent().remove_child(self)
	anchor.add_child(self)
	transform = Transform3D.IDENTITY
	collision_layer = 0
	collision_mask  = 0
	state = State.MOUNTED
	_held_by = null
	_mount_anchor = anchor
	_mount_vehicle = vehicle
	anchor.set_meta("mounted_tank", self)
	# Notify the vehicle so it can update its primary/secondary tank refs.
	if vehicle.has_method("on_lpg_tank_mounted"):
		vehicle.call("on_lpg_tank_mounted", self, anchor)

func _remove_from_mount(player: Node3D) -> void:
	# Hands full (already carrying a fresh bottle) → pop this one to the floor instead
	# of failing + leaving it half-removed. Otherwise pull it into the free hands. #14
	if player_holds_tank(player):
		eject_to_floor()
		return
	# Clear the mount's back-reference + tell the vehicle, then pick up.
	if _mount_anchor and _mount_anchor.has_meta("mounted_tank"):
		_mount_anchor.set_meta("mounted_tank", null)
	if _mount_vehicle and _mount_vehicle.has_method("on_lpg_tank_removed"):
		_mount_vehicle.call("on_lpg_tank_removed", self, _mount_anchor)
	_mount_anchor = null
	_mount_vehicle = null
	_pick_up(player)

## Pop a MOUNTED tank off onto the floor beside the vehicle — used for the one-action
## swap (a fresh tank mounting onto an occupied mount ejects the old one) and for
## removing with hands full. Clears the mount + notifies the vehicle. #14
func eject_to_floor() -> void:
	if state != State.MOUNTED:
		return
	var scene_root := get_tree().current_scene   # capture BEFORE detaching (get_tree() goes null)
	if scene_root == null:
		scene_root = get_tree().root
	var drop_world : Vector3 = global_position + Vector3(0.5, -0.3, 0.0)
	if _mount_anchor and _mount_anchor.has_meta("mounted_tank"):
		_mount_anchor.set_meta("mounted_tank", null)
	if _mount_vehicle and is_instance_valid(_mount_vehicle) and _mount_vehicle.has_method("on_lpg_tank_removed"):
		_mount_vehicle.call("on_lpg_tank_removed", self, _mount_anchor)
	_mount_anchor = null
	_mount_vehicle = null
	if get_parent():
		get_parent().remove_child(self)
	scene_root.add_child(self)
	global_transform = Transform3D(Basis(), drop_world)
	collision_layer = 1
	collision_mask  = 1
	state = State.FREE
	_held_by = null
	visible = true

# =============================================================================
# Find the nearest vehicle LPG mount within range of the held tank (for the
# "press E while holding to mount" interaction). Returns {anchor, vehicle} or
# null. Looks in the "vehicle" group, then searches each vehicle's children
# for nodes whose name starts with "LPG_Mount".
const MOUNT_SNAP_RANGE : float = 1.5
func _find_vehicle_mount() -> Dictionary:
	var best : Dictionary = {}
	var best_d := MOUNT_SNAP_RANGE
	for v in get_tree().get_nodes_in_group("vehicle"):
		var vn := v as Node3D
		if vn == null:
			continue
		for c in vn.get_children():
			if not (c is Node3D):
				continue
			if not (c as Node3D).name.begins_with("LPG_Mount"):
				continue
			# Occupied mounts are valid targets now — mounting onto one auto-ejects the
			# old tank (one-action swap). _mount_to handles the eject. #14
			var d := (c as Node3D).global_position.distance_to(global_position)
			if d < best_d:
				best_d = d
				best = {"anchor": c, "vehicle": v}
	return best

# =============================================================================
# UI prompts
# =============================================================================
func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
