extends StaticBody3D
class_name HoseNozzle

## Operator's water-hose nozzle / HP-washer pistol. Picked up from the owning reel
## or washer cart by pressing E; the holder spawns it into the player's hand and
## hands back a reference. LMB cycles the TIP ball valve through three positions:
## CLOSED → LITTLE → LOT → CLOSED. Water sprays only when BOTH the base valve
## (owned by the reel/cart) AND the tip valve are open; the effective spray rate
## is min(base, tip), then scaled by the nozzle's max_kg_per_s.
##
## Spray is a forward cone from the camera. Any FloorPile (dirt hotspot, shredder
## output mound, etc.) inside the cone gets scoop()'d at the effective rate, so a
## few seconds of spray clears a small heap.

const tool_id : String = "hose_nozzle"

enum TipValve { CLOSED, LITTLE, LOT }

## Set by the owning reel/cart when it deploys the nozzle. HP washer overrides
## these for a tighter, faster cone.
@export var max_kg_per_s        : float = 4.0
@export var max_range_m         : float = 4.0
@export var cone_half_angle_deg : float = 18.0
## Cosmetic only — colour-codes the nozzle handle (red for HP, brass for water).
@export var nozzle_tint         : Color = Color(0.82, 0.18, 0.16)

var _held_by    : Node3D = null
var _tip_valve  : int    = TipValve.CLOSED
var _owner_ref  : Node   = null     # back-ref to the HoseReel (or HP washer cart)
var _tether_mi  : MeshInstance3D = null
var _tether_mat : StandardMaterial3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("hose_nozzle")
	_build_visual()
	_build_tether()

func _build_visual() -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.76, 0.62, 0.20)
	brass.metallic = 0.85; brass.roughness = 0.30
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12); dark.roughness = 0.55
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = nozzle_tint; handle_mat.roughness = 0.45
	# Cylindrical body (the valve barrel) — local -Z is the spray direction.
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new(); bm.top_radius = 0.025; bm.bottom_radius = 0.035
	bm.height = 0.14; bm.radial_segments = 14
	body.mesh = bm; body.material_override = brass
	body.position = Vector3(0.0, 0.0, -0.07)
	body.rotation.x = deg_to_rad(90.0)
	add_child(body)
	# Valve lever sticking up — rotates to reflect tip valve state.
	var lever := MeshInstance3D.new()
	var lm := BoxMesh.new(); lm.size = Vector3(0.13, 0.018, 0.022)
	lever.mesh = lm; lever.material_override = handle_mat
	lever.name = "Lever"
	lever.position = Vector3(0.0, 0.04, -0.03)
	add_child(lever)
	# Tapered nozzle tip.
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new(); tm.top_radius = 0.012; tm.bottom_radius = 0.022
	tm.height = 0.06; tm.radial_segments = 12
	tip.mesh = tm; tip.material_override = dark
	tip.position = Vector3(0.0, 0.0, -0.17)
	tip.rotation.x = deg_to_rad(90.0)
	add_child(tip)
	# Small bounding collision for when dropped.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.16, 0.10, 0.30)
	col.shape = bx
	add_child(col)

func _build_tether() -> void:
	_tether_mi = MeshInstance3D.new()
	_tether_mi.name = "Tether"
	# The tether parents at world root so it draws from reel to nozzle without
	# inheriting the player's head transform.
	var tm := CylinderMesh.new()
	tm.top_radius = 0.022
	tm.bottom_radius = 0.022
	tm.height = 1.0
	tm.radial_segments = 8
	_tether_mi.mesh = tm
	_tether_mat = StandardMaterial3D.new()
	_tether_mat.albedo_color = Color(0.10, 0.10, 0.12)
	_tether_mat.roughness = 0.6
	_tether_mi.material_override = _tether_mat
	_tether_mi.visible = false

# =============================================================================
# DEPLOY / RETURN (called by HoseReel)
# =============================================================================
## Move into the player's hand. Called by the reel when E is pressed near it.
func attach_to_player(player: Node3D, owner_ref: Node) -> void:
	_held_by = player
	_owner_ref = owner_ref
	if get_parent():
		get_parent().remove_child(self)
	var head := player.get_node_or_null("Head") as Node3D
	var parent_node : Node = head if head != null else player
	parent_node.add_child(self)
	# Mounted under the camera like ShovelTool / WireCutter; nozzle points along -Z.
	transform = Transform3D(Basis(), Vector3(0.22, -0.20, -0.55))
	collision_layer = 0
	collision_mask  = 0
	# Slot into the inventory hotbar so 1-4 swaps still work.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("take", self)
	# Tether is drawn at world root (independent of the player transform).
	if _tether_mi != null and _tether_mi.get_parent() == null:
		var scene := get_tree().current_scene
		(scene if scene else get_tree().root).add_child(_tether_mi)

func _exit_tree() -> void:
	# Make sure the tether doesn't leak when we're freed.
	if _tether_mi != null and is_instance_valid(_tether_mi):
		_tether_mi.queue_free()

## Returns the nozzle to its owning reel/cart — closes the tip valve, removes from
## inventory, asks the owner to recover it (typically queue_free).
func return_to_owner() -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	_tip_valve = TipValve.CLOSED
	if _owner_ref != null and is_instance_valid(_owner_ref) and _owner_ref.has_method("on_nozzle_returned"):
		_owner_ref.call("on_nozzle_returned", self)
	_held_by = null

# =============================================================================
# INPUT
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	# E returns the nozzle to its reel/cart (closes everything).
	if event.is_action_pressed("interact"):
		return_to_owner()
		get_viewport().set_input_as_handled()
		return
	# LMB cycles the tip valve.
	if event.is_action_pressed("tool_use"):
		_tip_valve = (_tip_valve + 1) % 3
		_update_lever_angle()
		get_viewport().set_input_as_handled()
		return

func _update_lever_angle() -> void:
	# Rotate the lever to visually reflect valve state (in-place around its local Y).
	var lever := get_node_or_null("Lever") as MeshInstance3D
	if lever == null:
		return
	match _tip_valve:
		TipValve.CLOSED: lever.rotation.y = 0.0
		TipValve.LITTLE: lever.rotation.y = deg_to_rad(40.0)
		TipValve.LOT:    lever.rotation.y = deg_to_rad(85.0)

# =============================================================================
# SPRAY (per physics frame) — cone forward of the camera, scoops floor piles
# =============================================================================
## Effective spray rate kg/s. Both valves must be open; throttled by min(base,tip).
func _spray_rate() -> float:
	if _held_by == null or _tip_valve == TipValve.CLOSED:
		return 0.0
	if _owner_ref == null or not is_instance_valid(_owner_ref):
		return 0.0
	var base : int = int(_owner_ref.get("base_valve_state")) if "base_valve_state" in _owner_ref else 0
	if base == 0:
		return 0.0
	var lvl : int = min(base, _tip_valve)
	# LITTLE = 35% of max throttle, LOT = full.
	return max_kg_per_s * (0.35 if lvl == 1 else 1.0)

func _process(delta: float) -> void:
	_update_tether()
	if _held_by == null:
		return
	var rate := _spray_rate()
	if rate <= 0.0001:
		return
	# Aim is the camera forward direction (same convention as the leaf blower).
	var cam := _held_by.get_node_or_null("Head/Camera3D") as Camera3D
	var origin : Vector3
	var fwd    : Vector3
	if cam != null:
		origin = cam.global_position
		fwd = -cam.global_transform.basis.z.normalized()
	else:
		origin = global_position
		fwd = -global_transform.basis.z.normalized()
	var cos_half := cos(deg_to_rad(cone_half_angle_deg))
	var total_scooped := 0.0
	for p in get_tree().get_nodes_in_group("floor_pile"):
		if not (p is Node3D) or not is_instance_valid(p):
			continue
		var to_p : Vector3 = (p as Node3D).global_position - origin
		var d := to_p.length()
		if d > max_range_m or d < 0.05:
			continue
		if to_p.normalized().dot(fwd) < cos_half:
			continue
		# Inside the cone — scoop, but divide rate across piles so multiple piles
		# don't multiply the throughput per second.
		total_scooped += float(p.call("scoop", rate * delta))

## Draws a thick line from the owning reel/cart up to the held nozzle so the
## operator sees the hose pulling out. Hidden when not held.
func _update_tether() -> void:
	if _tether_mi == null:
		return
	if _held_by == null or _owner_ref == null or not is_instance_valid(_owner_ref):
		_tether_mi.visible = false
		return
	# Reel anchor: roughly the centre-of-mass of the reel body, ~1.1 m off the ground.
	var a : Vector3 = (_owner_ref as Node3D).global_position + Vector3(0.0, 1.1, 0.0)
	var b : Vector3 = global_position
	var diff := b - a
	var seg_len := diff.length()
	if seg_len < 0.01:
		_tether_mi.visible = false
		return
	(_tether_mi.mesh as CylinderMesh).height = seg_len
	# Build a basis whose +Y points along the hose direction (the cylinder mesh's
	# default axis is +Y), with X & Z any orthogonal pair.
	var up := diff / seg_len
	var ref := Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var x_axis := up.cross(ref).normalized()
	var z_axis := x_axis.cross(up).normalized()
	var mid := (a + b) * 0.5
	_tether_mi.global_transform = Transform3D(Basis(x_axis, up, z_axis), mid)
	_tether_mi.visible = true
