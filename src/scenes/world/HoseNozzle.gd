extends StaticBody3D
class_name HoseNozzle

## Operator's water-hose nozzle / HP-washer pistol with an Out-of-Ore-style ANCHOR
## CHAIN deployment mechanism.
##
## Two valves are still in play:
##   • BASE valve (lives on the reel; cycled by E at the reel)
##   • TIP  valve (LMB cycles CLOSED → LITTLE → LOT → CLOSED)
## Spray rate = max_kg_per_s × min(base, tip)-scale.
##
## CHAIN DEPLOYMENT — the difference from a simple tether:
##   1. While the operator walks AWAY from the last anchor, a new anchor is
##      automatically dropped every `segment_m` (default 1 m). The first anchor
##      is the reel itself; each new one fixes a new bend point on the floor.
##   2. The chain visual is one cylinder per inter-anchor segment + one last
##      cylinder from the last anchor up to the held nozzle — so the rope traces
##      the route the operator walked, NOT a straight line.
##   3. Pressing `hose_advance_back` (F) UN-anchors the LAST ground point. If no
##      ground anchors remain AND the operator is near the reel, the tip is
##      automatically returned to the reel. So the operator walks back, pressing
##      F at each anchor as they pass it, and the hose neatly reels itself in.
##   4. Total deployed length is hard-capped at `hose_length_m`. When the chain
##      is at max anchors no new ones are dropped — the operator can keep moving
##      but the last segment just gets visually stretched (no spray bonus).
##   5. Pressing `hotbar_drop` (Q) DROPS the tip in place: the nozzle becomes a
##      free pickable object at its current world position, and the chain stays
##      exactly where it was. Walk back and press E to pick it back up.
##
## The held nozzle stays parented under the player's Head (so the Inventory
## hotbar keeps working), but its global_position is overridden each frame to
## the chain-clamped point — so when the line is taut, the visible tip stays at
## the limit even if the operator's hand reaches further forward.

const tool_id : String = "hose_nozzle"

enum TipValve { CLOSED, LITTLE, LOT }
enum Mode     { ON_REEL, HELD, GROUNDED }

# Spray + chain config — reels/carts override these per their max_kg_per_s tier.
@export var max_kg_per_s        : float = 4.0
@export var max_range_m         : float = 4.0
@export var cone_half_angle_deg : float = 18.0
@export var nozzle_tint         : Color = Color(0.82, 0.18, 0.16)
@export var hose_length_m       : float = 10.0    # total hose length
@export var hose_segment_m      : float = 1.0     # distance between auto-anchors
@export var hose_radius         : float = 0.022   # visual hose tube radius
@export var pickup_radius       : float = 1.4     # how close to a grounded tip you must stand
@export var reel_dock_radius    : float = 1.6     # how close to the reel to auto-return
## Floor level the auto-dropped anchors rest on. The reel spout sits 1 m above
## this; subsequent anchors lie on the ground so the hose properly drops down.
@export var floor_y             : float = 0.0
## Catenary visual: each segment between consecutive anchors is subdivided into
## this many sub-segments, which sag toward the floor by SAG_RATIO × segment
## length. SUBDIVS = 1 falls back to straight lines (no sag); ≥4 reads as rope.
@export var chain_subdivs       : int   = 8
@export var chain_sag_ratio     : float = 0.18   # parabola depth as a fraction of seg length

var _held_by    : Node3D = null
var _tip_valve  : int    = TipValve.CLOSED
var _owner_ref  : Node   = null
var _mode       : int    = Mode.ON_REEL
var _player_near_grounded : bool = false
var _player_node : Node  = null
# Anchors in WORLD space. Index 0 is the reel (immutable; set in attach_to_player).
# Subsequent entries are auto-dropped as the operator walks; popped one at a
# time by F.
var _anchors    : Array  = []
# Visual chain — rebuilt every frame, parented at world root so it doesn't
# inherit the player's head transform.
var _chain_root : Node3D = null
var _chain_mat  : StandardMaterial3D = null
# A small Area3D added when the tip is GROUNDED so the operator can walk to it
# and press E to pick it back up. Re-removed on pickup.
var _ground_pickup_area : Area3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("hose_nozzle")
	_build_visual()
	_chain_mat = StandardMaterial3D.new()
	_chain_mat.albedo_color = Color(0.10, 0.10, 0.12)
	_chain_mat.roughness = 0.6

func _build_visual() -> void:
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.76, 0.62, 0.20)
	brass.metallic = 0.85; brass.roughness = 0.30
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12); dark.roughness = 0.55
	var handle_mat := StandardMaterial3D.new()
	handle_mat.albedo_color = nozzle_tint; handle_mat.roughness = 0.45
	# Valve body
	var body := MeshInstance3D.new()
	var bm := CylinderMesh.new(); bm.top_radius = 0.025; bm.bottom_radius = 0.035
	bm.height = 0.14; bm.radial_segments = 14
	body.mesh = bm; body.material_override = brass
	body.position = Vector3(0.0, 0.0, -0.07)
	body.rotation.x = deg_to_rad(90.0)
	add_child(body)
	# Lever — rotates to reflect tip valve state.
	var lever := MeshInstance3D.new()
	var lm := BoxMesh.new(); lm.size = Vector3(0.13, 0.018, 0.022)
	lever.mesh = lm; lever.material_override = handle_mat
	lever.name = "Lever"
	lever.position = Vector3(0.0, 0.04, -0.03)
	add_child(lever)
	# Tapered nozzle tip — local -Z is the spray direction.
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new(); tm.top_radius = 0.012; tm.bottom_radius = 0.022
	tm.height = 0.06; tm.radial_segments = 12
	tip.mesh = tm; tip.material_override = dark
	tip.position = Vector3(0.0, 0.0, -0.17)
	tip.rotation.x = deg_to_rad(90.0)
	add_child(tip)
	# Bounding collision (used when grounded — disabled while held).
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.16, 0.10, 0.30)
	col.shape = bx
	col.name = "BoundsCollision"
	add_child(col)

func _ensure_chain_root() -> void:
	if _chain_root != null and is_instance_valid(_chain_root):
		return
	_chain_root = Node3D.new()
	_chain_root.name = "HoseChain"
	var scene := get_tree().current_scene
	(scene if scene else get_tree().root).add_child(_chain_root)

# =============================================================================
# DEPLOY / RETURN / DROP / PICKUP — owned by mode transitions
# =============================================================================
## Move into the player's hand. Called by HoseReel.
func attach_to_player(player: Node3D, owner_ref: Node) -> void:
	_held_by = player
	_owner_ref = owner_ref
	_mode = Mode.HELD
	_player_near_grounded = false
	_player_node = null
	# Seed the chain with the reel as anchor 0 — every subsequent anchor sits
	# at hose_segment_m intervals from this point along the operator's path.
	_anchors.clear()
	if owner_ref is Node3D:
		_anchors.append((owner_ref as Node3D).global_position + Vector3(0.0, 1.0, 0.0))
	# Parent under head for the Inventory hotbar to work normally.
	if get_parent():
		get_parent().remove_child(self)
	var head := player.get_node_or_null("Head") as Node3D
	var parent_node : Node = head if head != null else player
	parent_node.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.22, -0.20, -0.55))
	collision_layer = 0
	collision_mask  = 0
	_set_bounds_disabled(true)
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("take", self)
	_ensure_chain_root()
	_remove_ground_pickup_area()

## F — advance back. Pops the LAST anchor (closest to the tip) if any. If the
## chain is empty (only the reel anchor remains) and the operator is within
## reel_dock_radius of the reel, the tip is returned to the reel automatically.
func advance_back() -> bool:
	if _mode != Mode.HELD:
		return false
	if _anchors.size() > 1:
		_anchors.pop_back()
		return true
	# Only the reel anchor remains — return tip if we're close enough to dock.
	if _owner_ref != null and is_instance_valid(_owner_ref):
		var reel_pos : Vector3 = (_owner_ref as Node3D).global_position
		if _held_by != null and (_held_by.global_position - reel_pos).length() <= reel_dock_radius:
			return_to_owner()
			return true
	return false

## Q — drop the tip in place. The chain stays exactly where it was; the nozzle
## becomes a free pickable object at its current world position.
func drop_in_place() -> void:
	if _mode != Mode.HELD or _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	# Capture the scene reference BEFORE detaching — get_tree() returns null once
	# we're orphaned from our parent, which would lose the reparent target.
	var tree := get_tree()
	var scene : Node = null
	if tree != null:
		scene = tree.current_scene if tree.current_scene != null else tree.root
	var world_pos := global_position
	if get_parent():
		get_parent().remove_child(self)
	if scene != null:
		scene.add_child(self)
	global_position = Vector3(world_pos.x, maxf(world_pos.y - 0.4, 0.05), world_pos.z)
	rotation = Vector3.ZERO
	_set_bounds_disabled(false)
	collision_layer = 1
	collision_mask  = 1
	visible = true
	_tip_valve = TipValve.CLOSED
	_update_lever_angle()
	_held_by = null
	_mode = Mode.GROUNDED
	_build_ground_pickup_area()

func _build_ground_pickup_area() -> void:
	_remove_ground_pickup_area()
	_ground_pickup_area = Area3D.new()
	_ground_pickup_area.name = "GroundPickup"
	_ground_pickup_area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = pickup_radius
	cs.shape = sp
	_ground_pickup_area.add_child(cs)
	add_child(_ground_pickup_area)
	_ground_pickup_area.body_entered.connect(_on_ground_player_entered)
	_ground_pickup_area.body_exited.connect(_on_ground_player_exited)

func _remove_ground_pickup_area() -> void:
	if _ground_pickup_area != null and is_instance_valid(_ground_pickup_area):
		_ground_pickup_area.queue_free()
	_ground_pickup_area = null
	_player_near_grounded = false
	_player_node = null

func _on_ground_player_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near_grounded = true
	_player_node = body
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Pak slang op  (E)")

func _on_ground_player_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near_grounded = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _pickup_from_ground(player: Node3D) -> void:
	if _mode != Mode.GROUNDED:
		return
	_held_by = player
	_mode = Mode.HELD
	if get_parent():
		get_parent().remove_child(self)
	var head := player.get_node_or_null("Head") as Node3D
	var parent_node : Node = head if head != null else player
	parent_node.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.22, -0.20, -0.55))
	collision_layer = 0
	collision_mask  = 0
	_set_bounds_disabled(true)
	_remove_ground_pickup_area()
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("take", self)
	# Chain stays exactly as it was — the operator's pick up resumes from the
	# same deployed configuration.

## Force-return: closes valves, frees the nozzle, notifies the reel/cart owner.
func return_to_owner() -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	_tip_valve = TipValve.CLOSED
	_anchors.clear()
	_clear_chain_visual()
	_remove_ground_pickup_area()
	_held_by = null
	_mode = Mode.ON_REEL
	if _owner_ref != null and is_instance_valid(_owner_ref) and _owner_ref.has_method("on_nozzle_returned"):
		_owner_ref.call("on_nozzle_returned", self)

func _exit_tree() -> void:
	if _chain_root != null and is_instance_valid(_chain_root):
		_chain_root.queue_free()
	if _ground_pickup_area != null and is_instance_valid(_ground_pickup_area):
		_ground_pickup_area.queue_free()

# =============================================================================
# INPUT
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _mode == Mode.GROUNDED:
		# Grounded: E to pick the tip back up; nothing else.
		if event.is_action_pressed("interact") and _player_near_grounded and _player_node != null:
			_pickup_from_ground(_player_node as Node3D)
			get_viewport().set_input_as_handled()
		return
	if _mode != Mode.HELD:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	# F — advance back: unanchor last point, or return tip if no anchors + at reel.
	if event.is_action_pressed("hose_advance_back"):
		advance_back()
		get_viewport().set_input_as_handled()
		return
	# Q — drop tip in place. Chain stays put; tip is pickable from the floor.
	if event.is_action_pressed("hotbar_drop"):
		drop_in_place()
		get_viewport().set_input_as_handled()
		return
	# LMB — cycle tip valve.
	if event.is_action_pressed("tool_use"):
		_tip_valve = (_tip_valve + 1) % 3
		_update_lever_angle()
		get_viewport().set_input_as_handled()
		return
	# E — only when at the reel, dock-return the tip (otherwise the reel itself
	# handles E to cycle base valve / pickup).
	if event.is_action_pressed("interact"):
		if _owner_ref != null and is_instance_valid(_owner_ref) and _held_by != null:
			var reel_pos : Vector3 = (_owner_ref as Node3D).global_position
			if (_held_by.global_position - reel_pos).length() <= reel_dock_radius:
				return_to_owner()
				get_viewport().set_input_as_handled()
				return

func _update_lever_angle() -> void:
	var lever := get_node_or_null("Lever") as MeshInstance3D
	if lever == null:
		return
	match _tip_valve:
		TipValve.CLOSED: lever.rotation.y = 0.0
		TipValve.LITTLE: lever.rotation.y = deg_to_rad(40.0)
		TipValve.LOT:    lever.rotation.y = deg_to_rad(85.0)

func _set_bounds_disabled(disabled: bool) -> void:
	var col := get_node_or_null("BoundsCollision") as CollisionShape3D
	if col != null:
		col.disabled = disabled

# =============================================================================
# PER-FRAME — chain auto-anchor + chain visual + spray
# =============================================================================
## Effective spray rate kg/s (gated by both valves; LITTLE = 35% throttle).
func _spray_rate() -> float:
	if _mode != Mode.HELD or _tip_valve == TipValve.CLOSED:
		return 0.0
	if _owner_ref == null or not is_instance_valid(_owner_ref):
		return 0.0
	var base : int = int(_owner_ref.get("base_valve_state")) if "base_valve_state" in _owner_ref else 0
	if base == 0:
		return 0.0
	var lvl : int = min(base, _tip_valve)
	return max_kg_per_s * (0.35 if lvl == 1 else 1.0)

## The world position the nozzle should sit at this frame: roughly the operator's
## hand (head + held_offset), clamped to within hose_segment_m of the last anchor
## so the rope stays "taut" between operator and last bend. Returns the operator's
## hand pos for spray aim if not held (defensive).
func _last_world_pos_when_held() -> Vector3:
	return global_position

func _process(_delta: float) -> void:
	if _mode == Mode.HELD:
		_tick_anchors_and_clamp_tip()
	_redraw_chain()
	if _mode != Mode.HELD:
		return
	var rate := _spray_rate()
	if rate <= 0.0001:
		return
	# Aim from the camera forward (same convention as the leaf blower / scanner).
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
	var dt := _delta
	for p in get_tree().get_nodes_in_group("floor_pile"):
		if not (p is Node3D) or not is_instance_valid(p):
			continue
		var to_p : Vector3 = (p as Node3D).global_position - origin
		var d := to_p.length()
		if d > max_range_m or d < 0.05:
			continue
		if to_p.normalized().dot(fwd) < cos_half:
			continue
		var _scooped : float = float(p.call("scoop", rate * dt))

## Each held-frame: maybe drop a new auto-anchor (if walked past last by >
## hose_segment_m AND below max anchor cap); then clamp the visible nozzle tip
## to within hose_segment_m of the last anchor so the chain visually stays taut.
func _tick_anchors_and_clamp_tip() -> void:
	if _anchors.is_empty() or _held_by == null:
		return
	var max_anchors : int = max(1, int(floor(hose_length_m / max(hose_segment_m, 0.05))))
	var last : Vector3 = _anchors.back()
	# Hand world position (set by the head parent + the fixed held local offset).
	var hand : Vector3 = global_position
	var diff : Vector3 = hand - last
	var diff_xz := Vector3(diff.x, 0.0, diff.z)
	var ground_dist : float = diff_xz.length()
	# Drop a fresh anchor once the operator has stepped past hose_segment_m from
	# the last anchor — but only if we have room left on the hose.
	if ground_dist > hose_segment_m and _anchors.size() < max_anchors:
		var step_dir : Vector3 = diff_xz / ground_dist
		# Place the new anchor on the FLOOR, exactly hose_segment_m further along
		# the path. The first anchor (the reel) sits at its mount height ~1 m up;
		# every subsequent anchor lies on the floor so the hose drops down from
		# the reel and trails along the ground, which catenary sag depends on.
		var anchor_pos : Vector3 = last + step_dir * hose_segment_m
		anchor_pos.y = floor_y
		_anchors.append(anchor_pos)
	# WALL: when the chain is at max anchors, the hose is taut — the player can
	# NOT walk further from the last anchor than hose_segment_m (a real wall). We
	# project them back along the over-extension vector each frame. This is gentle
	# because we only kick in once the chain is fully deployed.
	if _anchors.size() >= max_anchors:
		var diff_xz_after := Vector3((_held_by.global_position - _anchors.back()).x, 0.0,
			(_held_by.global_position - _anchors.back()).z)
		var d := diff_xz_after.length()
		if d > hose_segment_m and d > 0.001:
			var pushed : Vector3 = _anchors.back() + diff_xz_after / d * hose_segment_m
			pushed.y = _held_by.global_position.y   # don't yank them vertically
			_held_by.global_position = pushed

func _clear_chain_visual() -> void:
	if _chain_root == null or not is_instance_valid(_chain_root):
		return
	# Use immediate remove + queue_free so the next rebuild within the same frame
	# doesn't double-count children (queue_free alone is deferred to idle).
	for c in _chain_root.get_children():
		_chain_root.remove_child(c)
		c.queue_free()

## Rebuild the chain visual. Each pair of consecutive anchors becomes one rope
## span; each span is subdivided into chain_subdivs sub-cylinders along a
## downward parabola so the rope SAGS toward the floor between anchors instead
## of being a straight stick (a catenary approximation cheap enough to redraw
## every frame). The reel-to-first-floor-anchor span naturally drops because
## the reel anchor sits ~1 m above the floor.
func _redraw_chain() -> void:
	_ensure_chain_root()
	_clear_chain_visual()
	var pts : Array = _anchors.duplicate()
	# Append the nozzle world position as the last endpoint (held or grounded).
	if _mode != Mode.ON_REEL:
		pts.append(global_position)
	if pts.size() < 2:
		return
	for i in pts.size() - 1:
		var a : Vector3 = pts[i]
		var b : Vector3 = pts[i + 1]
		var seg_len : float = (b - a).length()
		if seg_len < 0.01:
			continue
		# Sag depth scales with segment length so longer spans hang lower.
		var sag : float = seg_len * chain_sag_ratio
		# Subdivide the span: sample chain_subdivs+1 points along a parabola
		# (lerp(a,b,t) + DOWN * sag * 4t(1-t)), draw cylinder between consecutive samples.
		var n : int = max(1, chain_subdivs)
		var prev : Vector3 = a
		for k in n:
			var t : float = float(k + 1) / float(n)
			var p : Vector3 = a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
			_draw_sub_cylinder(prev, p)
			prev = p

## Draw a single cylinder between two world points (used by _redraw_chain).
func _draw_sub_cylinder(a: Vector3, b: Vector3) -> void:
	var diff := b - a
	var len_ := diff.length()
	if len_ < 0.001:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = hose_radius
	cm.bottom_radius = hose_radius
	cm.height = len_
	cm.radial_segments = 6
	mi.mesh = cm
	mi.material_override = _chain_mat
	_chain_root.add_child(mi)
	var up : Vector3 = diff / len_
	var ref : Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var x_axis : Vector3 = up.cross(ref).normalized()
	var z_axis : Vector3 = x_axis.cross(up).normalized()
	mi.global_transform = Transform3D(Basis(x_axis, up, z_axis), (a + b) * 0.5)
