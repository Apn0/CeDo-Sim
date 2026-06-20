extends Node3D

class_name BaleYardManager

# =============================================================================
# #195 follow-up — Bale yard spawn / drain / proximity-sweep extracted out of
# MainWorld.gd.
# =============================================================================
# Owns:
#   • Initial yard fill from WorldLayout.bale_yards (polygon-aligned grid + MM
#     instances + per-bale collider job queue).
#   • The yard collider drain queue (#127 / #192) — time-sliced RB creation so
#     the world doesn't freeze for 60 s on a multi-thousand-bale layout.
#   • The yard RB proximity sweep (#143) — strips collision off bales >25 m
#     from the player so far yards don't churn the broad-phase every physics
#     tick, restores it when the player walks within reach.
#   • Shift-leader PC "Reset bales" / "Restock bales" buttons (#73 / #74) and
#     the ShiftClock callback that delivers the next-shift restock.
#
# MainWorld holds a reference to this manager and forwards reset_yard_bales /
# restock_yard_bales so ShiftLeaderTerminal.gd's `mw.call("reset_yard_bales")`
# path continues to work unchanged.

# Frame budget for the yard collider drain queue. 2 ms is enough to keep
# multi-thousand-bale layouts spawning steadily without showing as a hitch on
# the PerfHud.
const _YARD_SPAWN_BUDGET_USEC : int = 2000   # 2 ms / frame cap

# Proximity sweep parameters. 25 m matches the close-LOD MM swap, so colliders
# come online at exactly the radius the operator can interact with bales.
const _YARD_RB_NEAR_M  : float = 25.0
const _YARD_RB_TICK_S  : float = 0.5

# ── Runtime state ───────────────────────────────────────────────────────────
var _yard_spawn_queue : Array = []   # of Dictionary jobs (see _spawn_one_yard_bale)
var _yard_rb_tick_t   : float = 0.0
var _restock_pending  : bool  = false

# Reference back to MainWorld (parent) and the ShiftClock so we can wire the
# restock-on-shift-start signal in the same way the old in-MainWorld code did.
var _world       : Node = null
var _shift_clock : Node = null

# ── Public entry point ──────────────────────────────────────────────────────
## Called by MainWorld right after `add_child(bale_mgr)`. Captures the MainWorld
## reference + ShiftClock and immediately starts the layout-driven yard fill so
## the spawn order matches the old in-MainWorld code path.
func setup(world: Node, shift_clock: Node) -> void:
	_world = world
	_shift_clock = shift_clock
	_spawn_bale_yards_from_layout()

# ── _process slice (drain queue + proximity sweep) ──────────────────────────
## Called from MainWorld._process so MainWorld controls the per-frame ordering.
## Drains the bale-spawn backlog every frame within the budget, and runs the
## proximity sweep every _YARD_RB_TICK_S. Previously was a chunk of
## MainWorld._process; same behaviour, just relocated.
func tick(delta: float) -> void:
	# #192 — first, drain the bale-spawn backlog within our frame budget. This
	# is independent of the proximity tick cadence; we want to keep spawning
	# even between the 0.5 s proximity sweeps.
	_drain_yard_spawn_queue()
	_yard_rb_tick_t += delta
	if _yard_rb_tick_t < _YARD_RB_TICK_S:
		return
	_yard_rb_tick_t = 0.0
	var player : Node = null
	if _world != null and "player" in _world:
		player = _world.get("player")
	if player == null or not is_instance_valid(player):
		return
	var ppos : Vector3 = player.global_position
	var near_sq := _YARD_RB_NEAR_M * _YARD_RB_NEAR_M
	for rb in get_tree().get_nodes_in_group("yard_bale_rb"):
		if not is_instance_valid(rb):
			continue
		var d2 : float = (rb.global_position - ppos).length_squared()
		var near : bool = d2 < near_sq
		var on : bool = rb.collision_layer != 0
		if near and not on:
			rb.collision_layer = int(rb.get_meta("yard_rb_layer", 1))
			rb.collision_mask  = int(rb.get_meta("yard_rb_mask",  1))
		elif not near and on:
			rb.collision_layer = 0
			rb.collision_mask  = 0

# ── Yard layout spawn ───────────────────────────────────────────────────────
## Spawn bales inside each polygonal yard saved in WorldLayout, picking the
## supplier_id from the yard. Bales are tiled across the polygon footprint in a
## simple axis-aligned grid (rows × cols) clipped against the polygon — quick
## first pass; the full grid-rotated fill is task #25.
func _spawn_bale_yards_from_layout() -> void:
	if WorldLayout.bale_yards.is_empty():
		print("[BaleYardManager] No bale yards in layout"); return
	var yards_root := Node3D.new()
	yards_root.name = "BaleYards"
	_world.add_child(yards_root)
	var total_bales := 0
	var total_yards := 0
	for y in WorldLayout.bale_yards:
		var data : Dictionary = y
		var corners : Array = data.get("corners", [])
		if corners.size() < 3: continue
		var supplier_id : String = data.get("supplier_id", "")
		if supplier_id == "":
			push_warning("[BaleYardManager] Bale yard has no supplier_id — skipping")
			continue
		var origin_def : Dictionary = BaleDefs.get_origin(supplier_id)
		if origin_def.is_empty():
			push_warning("[BaleYardManager] Unknown supplier_id '%s' — skipping yard" % supplier_id)
			continue
		var size : Vector3 = origin_def.get("size", Vector3(1.1, 0.7, 1.1))
		var stack_high : int = int(origin_def.get("stack", 2))
		# Convert the polygon corners from layout-space (player-relative, north-up
		# RD) into scene-space via the same rotation-aware mapping the vehicles
		# use, so the yard sits in the right place + orientation on the building.
		var translated_corners : Array = []
		var yard_corrupt := false
		for c in corners:
			if not _world.call("_layout_rel_sane", c):
				yard_corrupt = true
				break
			translated_corners.append(_world.call("_layout_to_scene", c))
		if yard_corrupt:
			push_warning("[BaleYardManager] Yard '%s' has a corner km away from the anchor — corrupt layout data, skipping yard (redraw it in WorldSetup)" % supplier_id)
			continue
		corners = translated_corners
		# FIX (footprint shows as a triangle): if the user clicked corners in
		# Z-order (TL, TR, BL, BR) the polygon self-intersects into a bowtie and
		# point-in-polygon only fills a triangle. Re-sort the corners by angle
		# around their centroid so any 4 points form a proper convex quad.
		corners = _world.call("_sort_corners_ccw", corners)
		# Fill the polygon along ITS OWN LONGEST EDGE direction, not world X/Z. This
		# is what the user was missing: their rectangles are typically NOT axis-
		# aligned, so an axis-aligned grid only filled the diamond inscribed in the
		# polygon's AABB (the visible "diamond inside the rectangle" pattern). Now
		# bales are laid out along the polygon's actual edges, rotated to match,
		# filling the rectangle properly.
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
		# #102 — final NaN guard: if the polygon is degenerate (collinear corners,
		# zero-area, or any NaN-tainted coordinate that slipped past the sanity
		# check), the normalize path can still produce a non-finite u_axis. Drop
		# the yard rather than spawn bales with NaN transforms — those hit the
		# renderer every frame and saturate the error log (~46k errors).
		if not u_axis.is_finite() or u_axis.length_squared() < 0.5:
			push_warning("[BaleYardManager] Yard '%s' has degenerate polygon — skipping (redraw it)" % supplier_id)
			continue
		var v_axis : Vector3 = Vector3(-u_axis.z, 0.0, u_axis.x)   # 90° CCW in XZ
		# Polygon centroid (the grid pivot in WORLD space).
		var centroid := Vector3.ZERO
		for c in corners: centroid += c
		centroid /= float(corners.size())
		# Polygon UV extents in the (u,v) local basis (so the grid steps span the
		# real polygon extent — no diamond clipping).
		var min_u :=  INF; var max_u := -INF
		var min_v :=  INF; var max_v := -INF
		for c in corners:
			var cv : Vector3 = c
			var dv : Vector3 = cv - centroid
			# Renamed from u/v — same names are reused as the row-walking cursors
			# later in this function and the inner shadowing tripped
			# CONFUSABLE_LOCAL_DECLARATION.
			var pu : float = dv.dot(u_axis)
			var pv : float = dv.dot(v_axis)
			if pu < min_u: min_u = pu
			if pu > max_u: max_u = pu
			if pv < min_v: min_v = pv
			if pv > max_v: max_v = pv
		var poly2 : PackedVector2Array = _polygon_xz(corners)   # for point-in-poly check (world XZ)
		var yard_w : float = max_u - min_u
		var yard_d : float = max_v - min_v
		print("[BaleYardManager]  Yard '%s'  polygon-aligned %.1f × %.1f m  (stack %d)" \
			% [supplier_id, yard_w, yard_d, stack_high])
		# #61 follow-up — slightly wider step so adjacent bales read as
		# individual blocks rather than one continuous wall (operator: "Rotterdam
		# stack looks like a continuous super-long bale"). The MM body box is
		# size×0.98, so 0.25 m extra leaves a visible ~20 cm air-gap between
		# bales while keeping pack-density realistic.
		var step_x : float = size.x + 0.25
		var step_z : float = size.z + 0.25
		var floor_y : float = float(_world.call("_floor_top_y"))
		var yard_node := Node3D.new()
		yard_node.name = "Yard_%s" % supplier_id
		yards_root.add_child(yard_node)
		var nm : String = String(origin_def.get("name", supplier_id))
		var prefix : String = nm.substr(0, 3).to_upper()
		var bale_yaw : float = atan2(u_axis.x, u_axis.z)    # rotate each bale so its size.x aligns with the polygon edge
		# #61 — collect every (world_xy, level) the polygon would fill, FIRST,
		# so we can size the per-yard MultiMesh once before spawning bales. The
		# old per-bale build_node() + 13 MeshInstance3D children gave us ~30k
		# draw calls and 50-100k objs when yards were in view; the new path is
		# one MultiMesh per yard (= 1 draw call) plus colliders.
		var slots : Array = []   # each entry = [Vector3 pos, int level]
		var u := min_u + step_x * 0.5
		while u <= max_u:
			var v := min_v + step_z * 0.5
			while v <= max_v:
				var world_xy : Vector3 = centroid + u_axis * u + v_axis * v
				# #102 — last-line NaN gate. The renderer hits is_finite() once
				# per frame on every transform; a single bad bale would saturate
				# the error log. Drop the cell silently if the math went bad.
				if not world_xy.is_finite():
					v += step_z
					continue
				if Geometry2D.is_point_in_polygon(Vector2(world_xy.x, world_xy.z), poly2):
					for level in stack_high:
						slots.append([world_xy, level])
				v += step_z
			u += step_x
		var bales_this_yard : int = slots.size()
		if bales_this_yard > 0:
			# One MultiMesh sized to the whole yard.
			var mmi := PlaceableCatalog.build_yard_multimesh(supplier_id, bales_this_yard)
			# #117 — Close-LOD MM with groove-shaded bale material; visibility-
			# range swap with the far MM hides it past ~35 m so far-distance
			# draw count stays at 1 per yard. Close-range yards now show wire
			# shadow grooves on every bale face.
			var mmi_close := PlaceableCatalog.build_yard_multimesh_close(supplier_id, bales_this_yard)
			# #125 — Proximity-loaded paper sticker MM per yard. Stickers vanish
			# beyond STICKER_LOD_M (12 m) so far yards pay zero sticker cost; close
			# yards get the one-draw-call label pass.
			var mmi_sticker := PlaceableCatalog.build_yard_sticker_multimesh(supplier_id, bales_this_yard)
			if mmi != null:
				yard_node.add_child(mmi)
				# #243 — was 35 m with FADE_SELF (which fades both MMs to
				# fully TRANSPARENT around the threshold — operator saw bales
				# briefly disappear at the swap band, not swap). Now 25 m
				# with FADE_DISABLED for a hard cut: close MM hard-ends at
				# 25 m, far MM hard-begins at 25 m, no margin = no
				# transparent window. The close MM's per-bale slabs and wire
				# overlays inside _m_bale_simple already cap at 24 m, so the
				# 25 m hard-cut lines up with their cull and no double-render
				# is visible.
				const CLOSE_LOD_M : float = 25.0
				# #170 — was 12 m, but visibility_range_end on a MultiMeshInstance3D
				# culls the WHOLE INSTANCE, not per-bale. With a 30 m-wide yard the
				# yard centre sits ~15 m from the operator standing AT a bale, so
				# the entire sticker MM was already faded out (zero labels visible
				# in 5+ runs). 80 m is the new threshold so the operator always
				# sees stickers when within practical scan range of any yard.
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
				# Pass 1 — populate the MultiMesh transforms IMMEDIATELY. These are
				# just integer transform writes to the shared buffer and finish in
				# a fraction of a second even for 2940 instances. Bales render at
				# correct positions the moment the yard appears. Same transforms
				# go into BOTH MMs so far / close stay perfectly aligned during
				# the fade swap.
				for i in bales_this_yard:
					var entry : Array = slots[i]
					var pos : Vector3 = entry[0]
					var level : int = int(entry[1])
					var inst_origin := Vector3(
						pos.x,
						floor_y + size.y * float(level) + size_y_half,
						pos.z)
					var xf := Transform3D(bale_basis, inst_origin)
					mmi.multimesh.set_instance_transform(i, xf)
					if mmi_close != null:
						mmi_close.multimesh.set_instance_transform(i, xf)
					if mmi_sticker != null:
						# Sticker rides the +Z face at mid-height, 4 mm proud of the
						# bale skin so it doesn't z-fight. QuadMesh faces +Z by
						# default, which lines up with the bale's +Z face.
						var sticker_local := Vector3(0.0, 0.0, size.z * 0.49 + 0.004)
						var sticker_xf := Transform3D(bale_basis,
							inst_origin + bale_basis * sticker_local)
						mmi_sticker.multimesh.set_instance_transform(i, sticker_xf)
				# #127 — Pass 2: per-bale collider creation is the actual cost
				# (2940 RigidBody3D + CollisionShape3D + meta + group joins). The
				# old loop blocked >60 s. Push the job onto a time-sliced queue
				# that _process drains within a fixed per-frame budget — bounded
				# stutter regardless of total yard count, instead of a fan-out of
				# self-rescheduling call_deferred batches that can stack up.
				total_bales += bales_this_yard
				_yard_spawn_queue.push_back({
					"yard":     yard_node,
					"mmi":      mmi,
					"supplier": supplier_id,
					"prefix":   prefix,
					"slots":    slots,
					"floor_y":  floor_y,
					"size":     size,
					"yaw":      safe_yaw,
					"idx":      0,
				})
		print("[BaleYardManager]  Yard '%s' filled with %d bales  (1 multimesh draw call)" % [supplier_id, bales_this_yard])
		total_yards += 1
	print("[BaleYardManager] Bale yards from layout: %d bales across %d yards (RBs deferred)" % [total_bales, total_yards])

func _spawn_one_yard_bale(job: Dictionary) -> void:
	var yard_node : Node3D = job["yard"]
	var slots     : Array  = job["slots"]
	var i         : int    = int(job["idx"])
	var entry     : Array  = slots[i]
	var pos       : Vector3 = entry[0]
	var level     : int    = int(entry[1])
	var size      : Vector3 = job["size"]
	var yaw       : float  = job["yaw"]
	var rb := PlaceableCatalog.build_yard_bale_mm(
		job["supplier"] as String, job["mmi"] as MultiMeshInstance3D, i)
	if rb == null:
		return
	yard_node.add_child(rb)
	var spawn_pos := Vector3(pos.x, float(job["floor_y"]) + size.y * float(level), pos.z)
	rb.global_position = spawn_pos
	rb.rotation.y = yaw
	var code := "%s-%05d" % [job["prefix"] as String, (randi() % 100000)]
	rb.set_meta("bale_code", code)
	# #73 — origin pose so Reset Bales can snap moved bales back.
	rb.set_meta("yard_origin", spawn_pos)
	rb.set_meta("yard_origin_yaw", yaw)
	# #143 — proximity gate. Stash the spawn layer/mask, then turn collision
	# OFF. The periodic proximity sweep below re-enables only the RBs near
	# the player, so far yards (thousands of bales) don't churn collision
	# pairs every physics tick.
	rb.add_to_group("yard_bale_rb")
	rb.set_meta("yard_rb_layer", rb.collision_layer)
	rb.set_meta("yard_rb_mask",  rb.collision_mask)
	rb.collision_layer = 0
	rb.collision_mask  = 0

func _drain_yard_spawn_queue() -> void:
	if _yard_spawn_queue.is_empty():
		return
	var start_usec := Time.get_ticks_usec()
	while not _yard_spawn_queue.is_empty() \
			and (Time.get_ticks_usec() - start_usec) < _YARD_SPAWN_BUDGET_USEC:
		var job : Dictionary = _yard_spawn_queue[0]
		var yard_node : Node3D = job["yard"]
		# Yard may have been freed (world reload, save load) — drop the job.
		if yard_node == null or not is_instance_valid(yard_node):
			_yard_spawn_queue.pop_front()
			continue
		var slots : Array = job["slots"]
		if int(job["idx"]) >= slots.size():
			_yard_spawn_queue.pop_front()
			continue
		_spawn_one_yard_bale(job)
		job["idx"] = int(job["idx"]) + 1
		if int(job["idx"]) >= slots.size():
			_yard_spawn_queue.pop_front()

# =============================================================================
# SHIFT-LEADER PC — bale yard maintenance buttons (#73, #74)
# =============================================================================
## Snap every yard bale back to its spawn pose. Called from the shift-leader's
## "Reset bales" button. Cleans up: bales pushed off stacks by physics, bales
## still in their grabbed (detailed) form, bales that drifted >0.5 m from their
## original yard slot. Restores the multimesh slot for detailed bales so the
## yard renders normally again.
func reset_yard_bales() -> int:
	var n_reset : int = 0
	for b in get_tree().get_nodes_in_group("bale"):
		var rb := b as Node3D
		if rb == null or not is_instance_valid(rb):
			continue
		if not rb.has_meta("yard_origin"):
			continue   # not a yard-MM bale (forklift-placed elsewhere)
		var origin : Vector3 = rb.get_meta("yard_origin")
		var yaw    : float   = float(rb.get_meta("yard_origin_yaw", 0.0))
		var drift  : float   = rb.global_position.distance_to(origin)
		var was_detailed : bool = not bool(rb.get_meta("simple_bale", true))
		if drift < 0.05 and not was_detailed:
			continue   # already at rest
		# Snap pose.
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
		# If the bale was promoted to a detailed visual (Model children), strip it
		# and reveal the multimesh slot again — back to the cheap representation.
		if rb.has_meta("yard_mm_inst") and rb.has_meta("yard_mm_idx"):
			var mmi := rb.get_meta("yard_mm_inst") as MultiMeshInstance3D
			var idx := int(rb.get_meta("yard_mm_idx"))
			if mmi != null and mmi.multimesh != null \
					and idx >= 0 and idx < mmi.multimesh.instance_count:
				var bale_basis := Basis(Vector3.UP, yaw)
				# MM instances are CENTRE-positioned, body is BASE-positioned; the
				# half-height offset matches what _spawn_yards does at spawn.
				var size : Vector3 = BaleDefs.get_origin(
					String(rb.get_meta("material_origin", ""))).get("size", Vector3(1.1, 0.7, 1.1))
				var inst_origin := origin + Vector3(0.0, size.y * 0.5, 0.0)
				mmi.multimesh.set_instance_transform(idx,
					Transform3D(bale_basis, inst_origin))
		var model := rb.get_node_or_null("Model")
		if model != null:
			for ch in model.get_children():
				ch.queue_free()
			model.queue_free()   # detail_bale recreates it next time
		# Reset gameplay meta to "fresh bale" state.
		rb.set_meta("simple_bale", true)
		rb.set_meta("scanned", false)
		rb.set_meta("wires_cut", false)
		n_reset += 1
	print("[BaleYardManager] Reset %d yard bales" % n_reset)
	return n_reset

## Order a fresh yard restock from the shift-leader PC. v1 implementation: emit
## a walkie "logistiek" call NOW confirming the order, set a pending flag, and
## subscribe to ShiftClock.shift_started. On the next shift start the delivery
## confirmation fires and reset_yard_bales() runs to clear any drift / grabs
## that happened during the shift — net effect, the next shift opens with a
## "freshly stocked" yard.
##
## Persistence: _restock_pending is in-memory only; closing the game cancels a
## pending order. Wire to GameState in a v2 if persistence matters.
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
