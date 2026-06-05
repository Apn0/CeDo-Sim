extends Node

## Tool-placement mode — the "build tool, but for hand-held items."
##
## Built parallel to BuildMode (res://src/build/BuildMode.gd). Same shape of
## interaction (ghost preview at cursor, Q/E rotate, R/F height, LMB confirm,
## ESC cancel) — but instead of spawning a new machine from the catalog this
## mode RE-PLACES whatever tool is currently active in the player's Inventory.
##
## Why a separate mode: BuildMode is for laying down machinery (it owns its
## catalog UI, save format, and snaps to the building grid). Tool placement
## is the operator's natural day-to-day flow — pick up scissors, drive over,
## walk into the bunker, lay them on a bench — and conflating it with the
## factory-builder is dangerous (accidental machine spawns!). Hotkey is `G`.
##
## Behaviour:
##   • G with an active inventory tool       → ENTER placement (ghost preview)
##   • cursor over a Node3D in group "tool_slot" within snap range → SNAP to it
##   • Q / E                                  → rotate ghost ±15° around Y
##   • R / F                                  → raise / lower ghost ±10 cm
##   • LMB (build_place)                     → commit; tool leaves inventory
##   • ESC (build_cancel)                    → cancel; tool stays in hand
##
## Picking the tool back up afterwards uses the tool's existing pickup
## trigger (E near the tool, same as the first time you found it). That keeps
## the world boundary consistent — placed-in-world tools always behave the
## same whether they were dropped, placed, or spawned by MainWorld.

const SNAP_RANGE_M : float = 1.2      # how close cursor must be to a slot
const ROT_STEP     : float = deg_to_rad(15.0)
const HEIGHT_STEP  : float = 0.10
const PLACE_RANGE  : float = 6.0      # max distance from camera for ghost

# Runtime refs
var main_world : Node3D = null
var _ghost     : MeshInstance3D = null
var _ghost_rot_y : float = 0.0
var _ghost_y_off : float = 0.0       # extra height offset from R/F
var _placing   : bool   = false
var _tool      : Node3D = null       # the inventory tool we're placing
var _snap_slot : Node3D = null       # current snap target (or null)
var _camera    : Camera3D = null

# =============================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_actions()

## Fallback Input action registration — keeps `G` bound even if the saved
## InputMap is stale (same trick HUD does for map_toggle).
func _ensure_actions() -> void:
	if not InputMap.has_action("tool_place_mode"):
		InputMap.add_action("tool_place_mode")
		var k := InputEventKey.new()
		k.keycode = KEY_G
		InputMap.action_add_event("tool_place_mode", k)

## G-key context guard. Tool placement is an ON-FOOT action only — when the
## player is driving, G is the Merlo's telescope-retract; when building, G is
## the grid-snap toggle. Refuse to enter placement in either context so the key
## never double-fires.
func _can_use_placement() -> bool:
	var ctxs := get_tree().get_nodes_in_group("operator_context")
	if not ctxs.is_empty():
		var ctx = ctxs[0]
		if "current_mode" in ctx and String(ctx.current_mode) != "on_foot":
			return false
	if main_world and "build_mode" in main_world and main_world.build_mode != null:
		var bm = main_world.build_mode
		if "_state" in bm and int(bm._state) != 0:   # 0 == State.INACTIVE
			return false
	return true

# =============================================================================
# INPUT
# =============================================================================
func _input(event: InputEvent) -> void:
	# G toggles the mode IF we have a tool to place. But G is also bound to
	# build_grid_toggle (build mode) and forklift_tilt_fwd (Merlo telescope
	# retract in the cab). So only react to G when the player is ON FOOT and
	# NOT in build mode — otherwise let those other systems own the key.
	if event.is_action_pressed("tool_place_mode"):
		if not _placing and not _can_use_placement():
			return   # in a vehicle or building — G belongs to them, ignore
		if _placing:
			_cancel()
		else:
			_try_enter()
		get_viewport().set_input_as_handled()
		return
	if not _placing:
		return
	# Confirm / cancel.
	if event.is_action_pressed("build_place"):
		_commit()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()
		return
	# Rotate around Y.
	if event.is_action_pressed("build_rotate_cw"):
		_ghost_rot_y = wrapf(_ghost_rot_y + ROT_STEP, 0.0, TAU)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_rotate_ccw"):
		_ghost_rot_y = wrapf(_ghost_rot_y - ROT_STEP, 0.0, TAU)
		get_viewport().set_input_as_handled()
		return
	# Raise / lower.
	if event.is_action_pressed("build_raise"):
		_ghost_y_off += HEIGHT_STEP
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("build_lower"):
		_ghost_y_off -= HEIGHT_STEP
		get_viewport().set_input_as_handled()
		return

# =============================================================================
# ENTER / EXIT
# =============================================================================
func _try_enter() -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null:
		return
	var active : Node3D = inv.call("active") as Node3D
	if active == null:
		_toast("Nothing in hand to place.")
		return
	_tool = active
	_ghost = _make_ghost(_tool)
	if _ghost == null:
		_toast("Can't preview that tool — placement aborted.")
		_tool = null
		return
	get_tree().current_scene.add_child(_ghost)
	_placing = true
	_ghost_rot_y = 0.0
	_ghost_y_off = 0.0
	_snap_slot = null

func _cancel() -> void:
	_clear_ghost()
	_tool = null
	_snap_slot = null
	_placing = false

## Take the active inventory slot's mesh tree, deep-copy as a translucent
## "ghost" preview that follows the cursor. Just a visual — no collision.
func _make_ghost(src: Node3D) -> MeshInstance3D:
	# Find any MeshInstance3D under src to use as the silhouette. The tool's
	# first mesh child is plenty — it gets the silhouette across.
	var first_mesh : MeshInstance3D = null
	for n in _walk(src):
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			first_mesh = n
			break
	if first_mesh == null:
		return null
	var ghost := MeshInstance3D.new()
	ghost.name = "ToolGhost"
	ghost.mesh = first_mesh.mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.30, 1.00, 0.45, 0.45)
	m.flags_transparent = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost.material_override = m
	return ghost

func _clear_ghost() -> void:
	if _ghost == null:
		return
	if _ghost.get_parent():
		_ghost.get_parent().remove_child(_ghost)
	_ghost.queue_free()
	_ghost = null

# =============================================================================
# PER-FRAME — chase the cursor / snap to nearest slot
# =============================================================================
func _process(_delta: float) -> void:
	if not _placing or _ghost == null:
		return
	_camera = _resolve_camera()
	if _camera == null:
		return
	var hit := _raycast_from_centre()
	if hit.is_empty():
		_ghost.visible = false
		return
	_ghost.visible = true
	var point : Vector3 = hit.get("position", Vector3.ZERO)
	# Snap test — find the nearest tool_slot within SNAP_RANGE_M.
	_snap_slot = _nearest_slot(point)
	if _snap_slot != null:
		_ghost.global_position = _snap_slot.global_position + Vector3(0.0, _ghost_y_off, 0.0)
		_ghost.global_transform.basis = _snap_slot.global_transform.basis
		# Tint the ghost amber when snapped so the player sees the snap.
		_tint_ghost(Color(1.0, 0.75, 0.20, 0.55))
	else:
		_ghost.global_position = point + Vector3(0.0, _ghost_y_off, 0.0)
		_ghost.rotation = Vector3(0.0, _ghost_rot_y, 0.0)
		_tint_ghost(Color(0.30, 1.00, 0.45, 0.45))

func _tint_ghost(c: Color) -> void:
	var m := _ghost.material_override as StandardMaterial3D
	if m:
		m.albedo_color = c

func _nearest_slot(near: Vector3) -> Node3D:
	var best : Node3D = null
	var best_d := SNAP_RANGE_M
	for s in get_tree().get_nodes_in_group("tool_slot"):
		var sn := s as Node3D
		if sn == null:
			continue
		if not _slot_accepts(sn, _tool):   # cup holder only takes a coffee, etc.
			continue
		var d := sn.global_position.distance_to(near)
		if d < best_d:
			best_d = d
			best = sn
	return best

## A slot with an `accepts` metadata array only takes tools whose `tool_id` is
## listed (e.g. ToolSlot_CupHolder accepts ["coffee"]). Slots with no `accepts`
## meta take anything. So a sandwich won't snap into the cup holder.
func _slot_accepts(slot: Node3D, tool: Node3D) -> bool:
	if slot == null:
		return true
	if not slot.has_meta("accepts"):
		return true
	var acc : Array = slot.get_meta("accepts")
	if acc.is_empty():
		return true
	var tid := ""
	if tool != null and "tool_id" in tool:
		tid = String(tool.get("tool_id"))
	return tid in acc

func _raycast_from_centre() -> Dictionary:
	var vp := get_viewport()
	if vp == null:
		return {}
	if _camera == null:
		return {}
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var to := origin + dir * PLACE_RANGE
	var space := vp.world_3d.direct_space_state if vp.world_3d else null
	if space == null:
		return {}
	var q := PhysicsRayQueryParameters3D.create(origin, to)
	q.collision_mask = 0xFFFFFFFF
	# Exclude the player + the tool we're placing so we don't hit ourselves.
	var excl : Array = []
	if _tool is PhysicsBody3D:
		excl.append((_tool as PhysicsBody3D).get_rid())
	var p := _player_body()
	if p is PhysicsBody3D:
		excl.append((p as PhysicsBody3D).get_rid())
	q.exclude = excl
	return space.intersect_ray(q)

func _resolve_camera() -> Camera3D:
	# Use whichever camera is currently active.
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()

func _player_body() -> Node:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null:
		return null
	return inv.get("player_ref") as Node

# =============================================================================
# COMMIT — drop the tool at the ghost's position, clear inventory slot
# =============================================================================
func _commit() -> void:
	if _tool == null or _ghost == null:
		_cancel()
		return
	# Hand the tool back to the world: clear the slot in Inventory, reparent
	# the tool under scene root, place it at the ghost's pose, re-enable
	# collision. The tool's existing E-pickup will then work again.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", _tool)
	var scene_root := get_tree().current_scene
	if _tool.get_parent():
		_tool.get_parent().remove_child(_tool)
	scene_root.add_child(_tool)
	_tool.global_transform = _ghost.global_transform
	_tool.visible = true
	if _tool is CollisionObject3D:
		(_tool as CollisionObject3D).collision_layer = 1
		(_tool as CollisionObject3D).collision_mask  = 1
	if _snap_slot != null:
		_toast("Placed on %s" % _snap_slot.name)
	else:
		_toast("Placed.")
	_cancel()

# =============================================================================
# HELPERS
# =============================================================================
func _walk(n: Node) -> Array:
	var out : Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out

func _toast(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", "[place]  %s" % text, false)
	else:
		print("[place] %s" % text)
