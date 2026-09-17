extends Node3D

class_name BaleYardManager

# =============================================================================
# #195 follow-up — Bale yard spawn / drain / proximity-sweep extracted out of
# MainWorld.gd.
# =============================================================================

const _YARD_SPAWN_BUDGET_USEC : int = 2000   # DEAD — no readers
const _YARD_RB_NEAR_M  : float = 25.0        # DEAD — superseded by tick()'s NEAR_SQ
const _YARD_RB_TICK_S  : float = 0.5

class YardRecord:
	var supplier_id : String
	var yard_node   : Node3D
	var mmi         : MultiMeshInstance3D
	var centroid    : Vector3
	var radius      : float
	var slot_start  : int
	var slot_count  : int

class SlotRecord:
	var idx         : int
	var mmi_idx     : int
	var spawn_pos   : Vector3
	var yaw         : float
	var supplier    : String
	var prefix      : String
	var mmi         : MultiMeshInstance3D
	var yard_node   : Node3D
	var key_compat  : String

# ── Runtime state ───────────────────────────────────────────────────────────
var _yard_slots       : Array[SlotRecord] = []
var _yards            : Array[YardRecord] = []
var _active_bale_rbs  : Dictionary = {}          # int global_idx -> RigidBody3D
var _consumed_slots   : PackedByteArray          # size = _yard_slots.size(), 0=false, 1=true
var _key_to_slot_idx  : Dictionary = {}          # String key_compat -> int global_idx

# Persistent allocations to eliminate per-tick heap churn
var _sweep_points     : Array[Vector3] = []
var _despawn_scratch  : Array[int] = []
var _cached_vehicles  : Array[Node3D] = []
var _vehicle_cache_t  : float = 2.0              # Force immediate update on first tick

var _yard_rb_tick_t   : float = 0.0
var _restock_pending  : bool  = false
var _yard_polys       : Array[PackedVector2Array] = []

var _world       : Node = null
var _shift_clock : Node = null

# ── Public entry point ──────────────────────────────────────────────────────
func setup(world: Node, shift_clock: Node) -> void:
	_world = world
	_shift_clock = shift_clock
	_spawn_bale_yards_from_layout()
	_consumed_slots = PackedByteArray()
	_consumed_slots.resize(_yard_slots.size())
	_consumed_slots.fill(0)
	_update_vehicle_cache()

func get_yard_polygons() -> Array[PackedVector2Array]:
	return _yard_polys

func _update_vehicle_cache() -> void:
	_cached_vehicles.clear()
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v is Node3D and is_instance_valid(v):
			_cached_vehicles.append(v as Node3D)

# ── _process slice (proximity sweep & dynamic RB activation) ────────────────
func tick(delta: float) -> void:
	_vehicle_cache_t += delta
	if _vehicle_cache_t >= 2.0:
		_vehicle_cache_t = 0.0
		_update_vehicle_cache()
		
	_yard_rb_tick_t += delta
	if _yard_rb_tick_t < _YARD_RB_TICK_S:
		return
	_yard_rb_tick_t = 0.0
	
	_sweep_points.clear()
	var player : Node = null
	if _world != null and "player" in _world:
		player = _world.get("player")
	if player != null and is_instance_valid(player):
		_sweep_points.append(player.global_position)
		
	var valid_vehicles : Array[Node3D] = []
	for v in _cached_vehicles:
		if is_instance_valid(v):
			_sweep_points.append(v.global_position)
			valid_vehicles.append(v)
	_cached_vehicles = valid_vehicles
	
	if _sweep_points.is_empty():
		return

	const NEAR_SQ : float = 24.0 * 24.0
	const FAR_SQ  : float = 32.0 * 32.0

	# ---------------------------------------------------------
	# PHASE 1: DESPAWN
	# Direct dictionary iteration, no .keys() array allocation.
	# Checks ACTUAL RB global position to preserve ownership logic.
	# ---------------------------------------------------------
	_despawn_scratch.clear()
	for slot_idx in _active_bale_rbs:
		var slot : SlotRecord = _yard_slots[slot_idx]
		var tracked = _active_bale_rbs[slot_idx]
		var alive : bool = is_instance_valid(tracked)
		
		if not alive:
			_despawn_scratch.append(slot_idx)
			if slot_idx >= 0 and slot_idx < _consumed_slots.size():
				_consumed_slots[slot_idx] = 1
			continue
			
		var rb3 : Node3D = tracked as Node3D
		var rb_pos : Vector3 = rb3.global_position
		var min_d_sq : float = INF
		
		for pt in _sweep_points:
			var d_sq : float = (rb_pos - pt).length_squared()
			if d_sq < min_d_sq:
				min_d_sq = d_sq
			if min_d_sq < FAR_SQ:
				break # Early exit: already near, won't despawn!
				
		if min_d_sq > FAR_SQ:
			_despawn_scratch.append(slot_idx)
			
			var drift : float = rb_pos.distance_to(slot.spawn_pos)
			var was_detailed : bool = not bool(rb3.get_meta("simple_bale", true))
			var reparented : bool = (rb3.get_parent() != slot.yard_node)
			
			if drift > 0.35 or was_detailed or reparented:
				# Operator-owned / hauled bale: stays alive, slot is spent
				if slot_idx >= 0 and slot_idx < _consumed_slots.size():
					_consumed_slots[slot_idx] = 1
			else:
				# Pristine and far: despawn collider, restore MM visibility
				rb3.queue_free()
				
	for s_idx in _despawn_scratch:
		_active_bale_rbs.erase(s_idx)

	# ---------------------------------------------------------
	# PHASE 2: SPAWN 
	# Yard bounding sphere broadphase, skipping distant yards.
	# ---------------------------------------------------------
	for yard in _yards:
		var yard_min_d_sq : float = INF
		var centroid : Vector3 = yard.centroid
		var radius : float = yard.radius
		
		for pt in _sweep_points:
			var dist_to_center : float = centroid.distance_to(pt)
			var dist_to_edge : float = max(0.0, dist_to_center - radius)
			var d_sq : float = dist_to_edge * dist_to_edge
			if d_sq < yard_min_d_sq:
				yard_min_d_sq = d_sq
			if yard_min_d_sq < NEAR_SQ:
				break 
				
		if yard_min_d_sq >= NEAR_SQ:
			continue
			
		var start_idx : int = yard.slot_start
		var end_idx : int = start_idx + yard.slot_count
		for slot_idx in range(start_idx, end_idx):
			if _active_bale_rbs.has(slot_idx) or _consumed_slots[slot_idx] == 1:
				continue
				
			var slot : SlotRecord = _yard_slots[slot_idx]
			var slot_pos : Vector3 = slot.spawn_pos
			var min_d_sq : float = INF
			
			for pt in _sweep_points:
				var d_sq : float = (slot_pos - pt).length_squared()
				if d_sq < min_d_sq:
					min_d_sq = d_sq
				if min_d_sq < NEAR_SQ:
					break 
					
			if min_d_sq < NEAR_SQ:
				var rb := _spawn_slot_bale_rb(slot)
				if rb != null:
					_active_bale_rbs[slot_idx] = rb

# ── Yard layout spawn ───────────────────────────────────────────────────────
func _spawn_yard_pad(parent: Node3D, corners: Array, supplier_id: String) -> void:
	if corners.size() < 3:
		return
	var pts : Array = corners.duplicate()
	var n : Vector3 = (pts[1] - pts[0]).cross(pts[2] - pts[0])
	if n.y < 0.0:
		pts.reverse()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lift := Vector3.UP * 0.03
	for i in range(1, pts.size() - 1):
		st.add_vertex(pts[0] + lift)
		st.add_vertex(pts[i] + lift)
		st.add_vertex(pts[i + 1] + lift)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "YardPad_%s" % supplier_id
	mi.mesh = st.commit()
	var ph := get_node_or_null("/root/PolyhavenMaterials")
	if ph != null:
		mi.material_override = ph.call("ground_brick_pavement")
	parent.add_child(mi)

func _spawn_bale_yards_from_layout() -> void:
	if WorldLayout.bale_yards.is_empty():
		print("[BaleYardManager] No bale yards in layout"); return
	var yards_root := Node3D.new()
	yards_root.name = "BaleYards"
	_world.add_child(yards_root)
	var total_bales := 0
	var total_yards := 0
	
	var yard_idx := 0
	for y in WorldLayout.bale_yards:
		var n := _spawn_yard(y as Dictionary, yard_idx, yards_root)
		yard_idx += 1
		if n < 0:
			continue
		total_bales += n
		total_yards += 1
	print("[BaleYardManager] Bale yards from layout: %d bales across %d yards (proximity physics active)" % [total_bales, total_yards])

func _spawn_yard(data: Dictionary, yard_idx: int, yards_root: Node3D) -> int:
	var corners : Array = data.get("corners", [])
	if corners.size() < 3: return -1
	var supplier_id : String = data.get("supplier_id", "")
	if supplier_id == "":
		push_warning("[BaleYardManager] Bale yard has no supplier_id — skipping")
		return -1
	var origin_def : Dictionary = BaleDefs.get_origin(supplier_id)
	if origin_def.is_empty():
		push_warning("[BaleYardManager] Unknown supplier_id '%s' — skipping yard" % supplier_id)
		return -1
	var size : Vector3 = origin_def.get("size", Vector3(1.1, 0.7, 1.1))
	var stack_high : int = int(origin_def.get("stack", 2))
	
	var use_pc : bool = _world.has_node("/root/Plant") and Plant.is_initialized() and WorldLayout.has_pc_data
	var corners_pc : Array = []
	if use_pc and yard_idx >= 0 and yard_idx < WorldLayout.bale_yards_pc.size():
		corners_pc = (WorldLayout.bale_yards_pc[yard_idx] as Dictionary).get("corners_pc", [])
		if corners_pc.size() != corners.size():
			push_warning("[BaleYardManager] Yard '%s' PC corner count %d ≠ legacy %d — using legacy path" % [supplier_id, corners_pc.size(), corners.size()])
			use_pc = false
	elif use_pc:
		use_pc = false

	var translated_corners : Array = []
	var yard_corrupt := false
	for i in corners.size():
		var c : Vector3 = corners[i]
		if not _world.call("_layout_rel_sane", c):
			yard_corrupt = true
			break
		if use_pc:
			translated_corners.append(Plant.pc_to_scene(corners_pc[i]))
		else:
			translated_corners.append(_world.call("_layout_to_scene", c))
	if yard_corrupt:
		push_warning("[BaleYardManager] Yard '%s' has a corner km away from the anchor — corrupt layout data, skipping yard (redraw it in WorldSetup)" % supplier_id)
		return -1
	corners = translated_corners
	corners = _world.call("_sort_corners_ccw", corners)
	
	var yard_poly := PackedVector2Array()
	for cs in corners:
		var c3 : Vector3 = cs
		yard_poly.append(Vector2(c3.x, c3.z))
	_yard_polys.append(yard_poly)
	
	_spawn_yard_pad(yards_root, corners, supplier_id)
	
	var le_a : Vector3 = corners[0]; var le_b : Vector3 = corners[0]
	var le_len_sq : float = 0.0
	for i in corners.size():
		var ca : Vector3 = corners[i]
		var cb : Vector3 = corners[(i + 1) % corners.size()]
		var dd : float = (cb - ca).length_squared()
		if dd > le_len_sq:
			le_len_sq = dd; le_a = ca; le_b = cb
	var u_axis : Vector3 = (le_b - le_a)
	u_axis.y = 0.0
	u_axis = u_axis.normalized() if u_axis.length() > 0.001 else Vector3.RIGHT
	if not u_axis.is_finite() or u_axis.length_squared() < 0.5:
		push_warning("[BaleYardManager] Yard '%s' has degenerate polygon — skipping (redraw it)" % supplier_id)
		return -1
	var v_axis : Vector3 = Vector3(-u_axis.z, 0.0, u_axis.x)
	
	var centroid := Vector3.ZERO
	for c in corners: centroid += c
	centroid /= float(corners.size())
	
	var min_u :=  INF; var max_u := -INF
	var min_v :=  INF; var max_v := -INF
	for c in corners:
		var cv : Vector3 = c
		var dv : Vector3 = cv - centroid
		var pu : float = dv.dot(u_axis)
		var pv : float = dv.dot(v_axis)
		if pu < min_u: min_u = pu
		if pu > max_u: max_u = pu
		if pv < min_v: min_v = pv
		if pv > max_v: max_v = pv
	var poly2 : PackedVector2Array = _polygon_xz(corners)
	var yard_w : float = max_u - min_u
	var yard_d : float = max_v - min_v
	print("[BaleYardManager]  Yard '%s'  polygon-aligned %.1f × %.1f m  (stack %d)" \
		% [supplier_id, yard_w, yard_d, stack_high])
		
	var gap_rng := RandomNumberGenerator.new()
	gap_rng.seed = hash(supplier_id + "_yardgap")
	var GAP_MIN : float = 0.01
	var GAP_MAX : float = 0.06
	var step_x : float = size.x + (GAP_MIN + GAP_MAX) * 0.5
	var step_z : float = size.z + (GAP_MIN + GAP_MAX) * 0.5
	var floor_y : float = float(_world.call("_floor_top_y"))
	var yard_node := Node3D.new()
	yard_node.name = "Yard_%s" % supplier_id
	yards_root.add_child(yard_node)
	var nm : String = String(origin_def.get("name", supplier_id))
	var prefix : String = nm.substr(0, 3).to_upper()
	var bale_yaw : float = atan2(u_axis.x, u_axis.z)
	
	# Typed candidate storage removes internal array allocations
	var candidate_positions : Array[Vector3] = []
	var candidate_levels    : PackedInt32Array = PackedInt32Array()
	
	var u := min_u + step_x * 0.5
	while u <= max_u:
		var v := min_v + step_z * 0.5
		while v <= max_v:
			var world_xy : Vector3 = centroid + u_axis * u + v_axis * v
			if not world_xy.is_finite():
				v += size.z + gap_rng.randf_range(GAP_MIN, GAP_MAX)
				continue
			if Geometry2D.is_point_in_polygon(Vector2(world_xy.x, world_xy.z), poly2):
				for level in stack_high:
					candidate_positions.append(world_xy)
					candidate_levels.append(level)
			v += size.z + gap_rng.randf_range(GAP_MIN, GAP_MAX)
		u += size.x + gap_rng.randf_range(GAP_MIN, GAP_MAX)
		
	var bales_this_yard : int = candidate_positions.size()
	if bales_this_yard > 0:
		var mmi := PlaceableCatalog.build_yard_multimesh(supplier_id, bales_this_yard)
		var mmi_close := PlaceableCatalog.build_yard_multimesh_close(supplier_id, bales_this_yard)
		var mmi_sticker := PlaceableCatalog.build_yard_sticker_multimesh(supplier_id, bales_this_yard)
		if mmi != null:
			yard_node.add_child(mmi)
			const CLOSE_LOD_M : float = 25.0
			const STICKER_LOD_M : float = 80.0
			mmi.visibility_range_begin        = CLOSE_LOD_M
			mmi.visibility_range_begin_margin = 0.0
			mmi.visibility_range_fade_mode    = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if mmi_close != null:
				yard_node.add_child(mmi_close)
				mmi_close.visibility_range_end        = CLOSE_LOD_M
				mmi_close.visibility_range_end_margin = 0.0
				mmi_close.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			if mmi_sticker != null:
				yard_node.add_child(mmi_sticker)
				mmi_sticker.visibility_range_end        = STICKER_LOD_M
				mmi_sticker.visibility_range_end_margin = 2.0
				mmi_sticker.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				
			var safe_yaw : float = bale_yaw if is_finite(bale_yaw) else 0.0
			var bale_basis := Basis(Vector3.UP, safe_yaw)
			var size_y_half : float = size.y * 0.5
			
			var slot_start_idx : int = _yard_slots.size()
			var max_r_sq : float = 0.0
			
			for i in bales_this_yard:
				var pos : Vector3 = candidate_positions[i]
				var level : int = candidate_levels[i]
				var inst_origin := Vector3(
					pos.x,
					floor_y + size.y * float(level) + size_y_half,
					pos.z)
				var xf := Transform3D(bale_basis, inst_origin)
				mmi.multimesh.set_instance_transform(i, xf)
				if mmi_close != null:
					mmi_close.multimesh.set_instance_transform(i, xf)
				if mmi_sticker != null:
					var sticker_local := Vector3(0.0, 0.0, size.z * 0.49 + 0.004)
					var sticker_xf := Transform3D(bale_basis, inst_origin + bale_basis * sticker_local)
					mmi_sticker.multimesh.set_instance_transform(i, sticker_xf)
					
				var spawn_pos := Vector3(pos.x, floor_y + size.y * float(level), pos.z)
				var key_compat := "%s_%d_%d" % [supplier_id, yard_idx, i]
				
				var slot := SlotRecord.new()
				slot.idx = _yard_slots.size()
				slot.mmi_idx = i
				slot.spawn_pos = spawn_pos
				slot.yaw = safe_yaw
				slot.supplier = supplier_id
				slot.prefix = prefix
				slot.mmi = mmi
				slot.yard_node = yard_node
				slot.key_compat = key_compat
				
				_yard_slots.append(slot)
				_key_to_slot_idx[key_compat] = slot.idx
				
				var d_sq : float = spawn_pos.distance_squared_to(centroid)
				if d_sq > max_r_sq:
					max_r_sq = d_sq
					
			var bale_margin : float = sqrt(size.x * size.x + size.z * size.z) * 0.5
			var yard_radius : float = sqrt(max_r_sq) + bale_margin

			var yard_rec := YardRecord.new()
			yard_rec.supplier_id = supplier_id
			yard_rec.yard_node = yard_node
			yard_rec.mmi = mmi
			yard_rec.centroid = centroid
			yard_rec.radius = yard_radius
			yard_rec.slot_start = slot_start_idx
			yard_rec.slot_count = bales_this_yard
			_yards.append(yard_rec)
			
		print("[BaleYardManager]  Yard '%s' filled with %d bales  (1 multimesh draw call)" % [supplier_id, bales_this_yard])
	return bales_this_yard

func _spawn_slot_bale_rb(slot: SlotRecord) -> RigidBody3D:
	var yard_node : Node3D = slot.yard_node
	if yard_node == null or not is_instance_valid(yard_node):
		return null
	var rb := PlaceableCatalog.build_yard_bale_mm(
		slot.supplier, slot.mmi, slot.mmi_idx)
	if rb == null:
		return null
	yard_node.add_child(rb)
	var spawn_pos : Vector3 = slot.spawn_pos
	var yaw : float = slot.yaw
	rb.global_position = spawn_pos
	rb.rotation.y = yaw
	var code := "%s-%05d" % [slot.prefix, (randi() % 100000)]
	rb.set_meta("bale_code", code)
	rb.set_meta("yard_origin", spawn_pos)
	rb.set_meta("yard_origin_yaw", yaw)
	# Dual-registration for perfect backward/forward compatibility
	rb.set_meta("slot_key", slot.key_compat) 
	rb.set_meta("slot_idx", slot.idx)
	rb.add_to_group("yard_bale_rb")
	return rb as RigidBody3D

# =============================================================================
# SHIFT-LEADER PC — bale yard maintenance buttons (#73, #74)
# =============================================================================
func reset_yard_bales() -> int:
	var n_reset : int = 0
	_active_bale_rbs.clear()
	for b in get_tree().get_nodes_in_group("bale"):
		var rb := b as Node3D
		if rb == null or not is_instance_valid(rb):
			continue
		if not rb.has_meta("yard_origin"):
			continue   
			
		var origin : Vector3 = rb.get_meta("yard_origin")
		
		# Resolve slot index with strict identity and bounds checking
		var target_slot_idx : int = -1
		if rb.has_meta("slot_key"):
			target_slot_idx = _key_to_slot_idx.get(String(rb.get_meta("slot_key")), -1)
		elif rb.has_meta("slot_idx"):
			var raw_idx = rb.get_meta("slot_idx")
			if typeof(raw_idx) == TYPE_INT:
				var sidx : int = raw_idx
				if sidx >= 0 and sidx < _yard_slots.size():
					if _yard_slots[sidx].spawn_pos.is_equal_approx(origin):
						target_slot_idx = sidx
			
		if target_slot_idx >= 0 and target_slot_idx < _consumed_slots.size():
			_active_bale_rbs[target_slot_idx] = rb
			_consumed_slots[target_slot_idx] = 0
		var yaw    : float   = float(rb.get_meta("yard_origin_yaw", 0.0))
		var drift  : float   = rb.global_position.distance_to(origin)
		var was_detailed : bool = not bool(rb.get_meta("simple_bale", true))
		if drift < 0.05 and not was_detailed:
			continue   
			
		if rb is RigidBody3D:
			var rbody := rb as RigidBody3D
			rbody.linear_velocity = Vector3.ZERO
			rbody.angular_velocity = Vector3.ZERO
			rbody.freeze = true
			rbody.sleeping = true
			rbody.collision_layer = 1
			rbody.collision_mask = 1
		rb.global_position = origin
		rb.rotation.y = yaw
		
		if rb.has_meta("yard_mm_inst") and rb.has_meta("yard_mm_idx"):
			var mmi := rb.get_meta("yard_mm_inst") as MultiMeshInstance3D
			var idx := int(rb.get_meta("yard_mm_idx"))
			if mmi != null and mmi.multimesh != null \
					and idx >= 0 and idx < mmi.multimesh.instance_count:
				var bale_basis := Basis(Vector3.UP, yaw)
				var size : Vector3 = BaleDefs.get_origin(
					String(rb.get_meta("material_origin", ""))).get("size", Vector3(1.1, 0.7, 1.1))
				var inst_origin := origin + Vector3(0.0, size.y * 0.5, 0.0)
				mmi.multimesh.set_instance_transform(idx,
					Transform3D(bale_basis, inst_origin))
					
		var model := rb.get_node_or_null("Model")
		if model != null:
			for ch in model.get_children():
				ch.queue_free()
			model.queue_free()   
			
		rb.set_meta("simple_bale", true)
		rb.set_meta("scanned", false)
		rb.set_meta("wires_cut", false)
		n_reset += 1
		
	print("[BaleYardManager] Reset %d yard bales" % n_reset)
	return n_reset

func restock_yard_bales() -> int:
	if _restock_pending:
		var walkie_dup := get_node_or_null("/root/Walkie")
		if walkie_dup and walkie_dup.has_method("receive_call"):
			walkie_dup.call("receive_call", "Logistiek",
				"Bestelling al ingepland voor de volgende dienst — geen dubbele levering.")
		return 0
	var walkie := get_node_or_null("/root/Walkie")
	if walkie and walkie.has_method("receive_call"):
		walkie.call("receive_call", "Logistiek",
			"Bestelling ontvangen — nieuwe balen worden geleverd bij de start van de volgende dienst.")
	if _shift_clock and _shift_clock.has_signal("shift_started"):
		var c := Callable(self, "_on_shift_started_restock")
		if not _shift_clock.shift_started.is_connected(c):
			_shift_clock.shift_started.connect(c)
	_restock_pending = true
	print("[BaleYardManager] Restock ordered — delivery on next shift_started")
	return 1

func _on_shift_started_restock() -> void:
	if not _restock_pending:
		return
	_restock_pending = false
	var n := reset_yard_bales()
	var walkie := get_node_or_null("/root/Walkie")
	if walkie and walkie.has_method("receive_call"):
		walkie.call("receive_call", "Logistiek",
			"Levering aangekomen — %d balen aangevuld voor de nieuwe dienst." % n)
	print("[BaleYardManager] Restock delivered — %d bales refreshed" % n)

func _polygon_xz(corners: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in corners:
		out.append(Vector2(c.x, c.z))
	return out
