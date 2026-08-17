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

# RETIRED (2026-08-16 audit): frame budget for the old time-sliced yard collider
# drain queue. That queue no longer exists — tick()'s proximity sweep creates
# colliders on demand instead — so this constant has had ZERO readers since the
# sweep landed (repo-wide grep: this line only). Kept, not deleted, so a reader
# of a log line or doc that still quotes "2 ms/frame" can find the retirement
# note instead of a live-looking knob. Do not wire it back up without a doc.
const _YARD_SPAWN_BUDGET_USEC : int = 2000   # DEAD — no readers

# RETIRED (2026-08-16 audit): the sweep radius lives in tick() as NEAR_SQ (24 m)
# / FAR_SQ (32 m hysteresis); this 25 m copy has zero readers and disagrees with
# the value that actually runs — the stale-constant pattern this project keeps
# getting bitten by. Read tick(), not this line.
const _YARD_RB_NEAR_M  : float = 25.0        # DEAD — superseded by tick()'s NEAR_SQ
const _YARD_RB_TICK_S  : float = 0.5

# ── Runtime state ───────────────────────────────────────────────────────────
var _yard_slots       : Array[Dictionary] = []   # of slot definition dicts
var _active_bale_rbs  : Dictionary = {}          # String slot_key -> RigidBody3D
var _yard_rb_tick_t   : float = 0.0
var _restock_pending  : bool  = false

## Slot keys whose bale has LEFT the yard's control: grabbed and hauled away,
## reparented onto a vehicle, or freed outright (LineFlow.gd:2085 frees a bale
## once remaining_kg hits 0, BaleBurst.gd:115 frees the husk when it is opened).
##
## A consumed slot is NEVER refilled. The yard is a finite stock delivered by
## truck; the only documented way more bales appear is the shift-leader's
## restock order (restock_yard_bales → reset_yard_bales), and no plant doc
## authorises a slot growing a replacement bale on its own.
##
## 2026-08-16 audit C1/C2 — before this set existed, tick()'s far-branch erased
## the slot key on the KEEP-ALIVE path too. Grab a yard bale, haul it past 32 m,
## come back inside 24 m: the slot had no key, so a SECOND bale was minted in it
## while the first was still in the forks (unbounded mass creation, C1), and the
## new body was invisible-but-solid because detail_bale() had already zero-scaled
## that slot's MultiMesh instance and nothing restores it (C2).
var _consumed_slots   : Dictionary = {}          # String slot_key -> true (a set)

## Yard perimeters in SCENE XZ, captured as each yard is built. These are the
## positions the pad and bales were ACTUALLY spawned at, not a re-derivation
## from layout data — a consumer drawing them (the site map's yard layer) can
## therefore never disagree with the bales standing in them. Corrupt and
## unknown-supplier yards are skipped before this point, so the list holds only
## yards that exist in the world.
var _yard_polys : Array[PackedVector2Array] = []

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

## Scene-XZ yard perimeters, CCW-ordered, in spawn order. Empty before setup()
## and on layouts with no yards; consumers must handle that rather than
## substituting a guess.
func get_yard_polygons() -> Array[PackedVector2Array]:
	return _yard_polys

# ── _process slice (proximity sweep & dynamic RB activation) ────────────────
## Called from MainWorld._process so MainWorld controls the per-frame ordering.
## Dynamically instantiates RigidBody3D colliders ONLY for bales near the player
## or vehicles, and frees untouched distant colliders. This prevents thousands
## of idle RigidBody3D nodes from saturating the physics server and SceneTree.
func tick(delta: float) -> void:
	_yard_rb_tick_t += delta
	if _yard_rb_tick_t < _YARD_RB_TICK_S:
		return
	_yard_rb_tick_t = 0.0
	var sweep_points : Array[Vector3] = []
	var player : Node = null
	if _world != null and "player" in _world:
		player = _world.get("player")
	if player != null and is_instance_valid(player):
		sweep_points.append(player.global_position)
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v is Node3D and is_instance_valid(v):
			sweep_points.append((v as Node3D).global_position)
	if sweep_points.is_empty():
		return

	const NEAR_SQ : float = 24.0 * 24.0   # 24m spawn radius
	const FAR_SQ  : float = 32.0 * 32.0   # 32m despawn radius (hysteresis)

	for slot in _yard_slots:
		var slot_pos : Vector3 = slot["spawn_pos"]
		var min_d_sq : float = 1e12
		for pt in sweep_points:
			var d_sq : float = (slot_pos - pt).length_squared()
			if d_sq < min_d_sq:
				min_d_sq = d_sq

		var key : String = slot["key"]
		# Untyped on purpose: the dictionary can still hold a body something else
		# freed this frame, and assigning a freed instance to a typed Node3D local
		# is itself an error in Godot 4.
		#
		# Liveness is `has(key) and is_instance_valid(...)`, NEVER `tracked != null`:
		# measured 2026-08-16, a Variant holding a FREED Object compares EQUAL to
		# null in Godot 4, so a `!= null` guard silently skips the dead-body case
		# and the slot then looks empty and refillable — the very bug this block
		# exists to stop.
		var tracked = _active_bale_rbs.get(key, null)
		var alive : bool = _active_bale_rbs.has(key) and is_instance_valid(tracked)
		if _active_bale_rbs.has(key) and not alive:
			# Someone else freed this bale — LineFlow fed it into the line
			# (LineFlow.gd:2085), or BaleBurst opened it (BaleBurst.gd:115). The
			# slot is spent: drop the dangling reference and record that it must
			# never be refilled.
			_active_bale_rbs.erase(key)
			_consumed_slots[key] = true

		if min_d_sq < NEAR_SQ:
			# Spawn a collider ONLY for a slot that still holds its own bale.
			# _consumed_slots is what keeps this from minting a duplicate of a
			# bale that is currently in the operator's forks (audit C1) — and,
			# because a consumed slot's MultiMesh instance is zero-scaled and
			# never restored here, from minting an invisible solid one (C2).
			if not alive and not _consumed_slots.has(key):
				var rb := _spawn_slot_bale_rb(slot)
				if rb != null:
					_active_bale_rbs[key] = rb
		elif min_d_sq > FAR_SQ:
			if alive:
				var rb3 : Node3D = tracked as Node3D
				var drift : float = rb3.global_position.distance_to(slot_pos)
				var was_detailed : bool = not bool(rb3.get_meta("simple_bale", true))
				var reparented : bool = (rb3.get_parent() != slot["yard"])
				if drift > 0.35 or was_detailed or reparented:
					# Grabbed by clamp/forks, hauled off, or riding a vehicle. The
					# BODY stays alive — it is the operator's bale now — but the
					# SLOT is spent and must not grow a replacement.
					_active_bale_rbs.erase(key)
					_consumed_slots[key] = true
				else:
					# Pristine, still in its slot, and far from every sweep point:
					# free the body. Its MultiMesh instance is untouched (still
					# full scale), so the operator keeps seeing the bale and the
					# next approach re-creates an identical collider. NOT consumed.
					_active_bale_rbs.erase(key)
					rb3.queue_free()

# ── Yard layout spawn ───────────────────────────────────────────────────────
## Spawn bales inside each polygonal yard saved in WorldLayout, picking the
## supplier_id from the yard. Bales are tiled across the polygon footprint in a
## simple axis-aligned grid (rows × cols) clipped against the polygon — quick
## first pass; the full grid-rotated fill is task #25.
## Brick-paved pad under one yard polygon (triangle fan over the CCW-sorted
## convex corners, 3 cm proud of the ground to avoid z-fighting). Operator
## states the real bale lot is brick paving — Polyhaven brick_pavement_03.
func _spawn_yard_pad(parent: Node3D, corners: Array, supplier_id: String) -> void:
	if corners.size() < 3:
		return
	var pts : Array = corners.duplicate()
	# Godot front faces wind clockwise; an upward-facing triangle's right-hand
	# cross normal is +Y in that order. Flip if the sorted order faces down.
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
	for yard_idx in WorldLayout.bale_yards.size():
		var y : Dictionary = WorldLayout.bale_yards[yard_idx]
		var bales_spawned : int = _spawn_yard(y, yard_idx, yards_root)
		if bales_spawned >= 0:
			total_bales += bales_spawned
			total_yards += 1
	print("[BaleYardManager] Bale yards from layout: %d bales across %d yards (RBs deferred)" % [total_bales, total_yards])

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
			push_warning("[BaleYardManager] Yard '%s' has a corner km away from the anchor — corrupt layout data, skipping yard (fix the corner in world_layout.json; WorldSetup was deleted 2026-08-17)" % supplier_id)
			continue
		corners = translated_corners
		# FIX (footprint shows as a triangle): if the user clicked corners in
		# Z-order (TL, TR, BL, BR) the polygon self-intersects into a bowtie and
		# point-in-polygon only fills a triangle. Re-sort the corners by angle
		# around their centroid so any 4 points form a proper convex quad.
		corners = _world.call("_sort_corners_ccw", corners)
		# Record the final scene-frame perimeter (post-sort, so it matches the pad
		# and the fill grid exactly) for get_yard_polygons() consumers.
		var yard_poly := PackedVector2Array()
		for cs in corners:
			var c3 : Vector3 = cs
			yard_poly.append(Vector2(c3.x, c3.z))
		_yard_polys.append(yard_poly)
		# Operator pick (2026-07): the real bale lot is brick-paved — lay a
		# Polyhaven brick_pavement_03 pad under the yard polygon.
		_spawn_yard_pad(yards_root, corners, supplier_id)
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
		# Randomized 1–6 cm gap between adjacent bales (operator spec). Real yard
		# bales are packed tight and irregular, not on an airy regular grid. Each
		# grid step adds the bale footprint plus a small random gap; seeded per
		# supplier so the layout is stable across reloads.
		var gap_rng := RandomNumberGenerator.new()
		gap_rng.seed = hash(supplier_id + "_yardgap")
		var GAP_MIN : float = 0.01
		var GAP_MAX : float = 0.06
		# Nominal cell (used only for the starting half-cell offset; the per-step
		# increments below are randomized within [GAP_MIN, GAP_MAX]).
		var step_x : float = size.x + (GAP_MIN + GAP_MAX) * 0.5
		var step_z : float = size.z + (GAP_MIN + GAP_MAX) * 0.5
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
					v += size.z + gap_rng.randf_range(GAP_MIN, GAP_MAX)
					continue
				if Geometry2D.is_point_in_polygon(Vector2(world_xy.x, world_xy.z), poly2):
					for level in stack_high:
						slots.append([world_xy, level])
				v += size.z + gap_rng.randf_range(GAP_MIN, GAP_MAX)
			u += size.x + gap_rng.randf_range(GAP_MIN, GAP_MAX)
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
					mmi_close.multimesh.set_instance_transform(i, xf)
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
				# Pass 2: Register slot metadata for dynamic proximity activation.
				# Instead of allocating thousands of RigidBody3D nodes upfront,
				# the proximity sweep in tick() only instantiates colliders near
				# the player and active vehicles, saving thousands of physics bodies.
				for i in bales_this_yard:
					var entry : Array = slots[i]
					var pos : Vector3 = entry[0]
					var level : int = int(entry[1])
					var spawn_pos := Vector3(pos.x, floor_y + size.y * float(level), pos.z)
					var slot_key := "%s_%d_%d" % [supplier_id, yard_idx, i]
					_yard_slots.append({
						"key":       slot_key,
						"yard":      yard_node,
						"mmi":       mmi,
						"supplier":  supplier_id,
						"prefix":    prefix,
						"spawn_pos": spawn_pos,
						"size":      size,
						"yaw":       safe_yaw,
						"idx":       i,
					})
				total_bales += bales_this_yard
		print("[BaleYardManager]  Yard '%s' filled with %d bales  (1 multimesh draw call)" % [supplier_id, bales_this_yard])
		total_yards += 1
	print("[BaleYardManager] Bale yards from layout: %d bales across %d yards (proximity physics active)" % [total_bales, total_yards])

func _spawn_slot_bale_rb(slot: Dictionary) -> RigidBody3D:
	var yard_node : Node3D = slot["yard"]
	if yard_node == null or not is_instance_valid(yard_node):
		return null
	var i : int = int(slot["idx"])
	var rb := PlaceableCatalog.build_yard_bale_mm(
		slot["supplier"] as String, slot["mmi"] as MultiMeshInstance3D, i)
	if rb == null:
		return null
	yard_node.add_child(rb)
	var spawn_pos : Vector3 = slot["spawn_pos"]
	var yaw : float = float(slot["yaw"])
	rb.global_position = spawn_pos
	rb.rotation.y = yaw
	var code := "%s-%05d" % [slot["prefix"] as String, (randi() % 100000)]
	rb.set_meta("bale_code", code)
	rb.set_meta("yard_origin", spawn_pos)
	rb.set_meta("yard_origin_yaw", yaw)
	rb.set_meta("slot_key", slot["key"])
	rb.add_to_group("yard_bale_rb")
	return rb as RigidBody3D

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
	_active_bale_rbs.clear()
	for b in get_tree().get_nodes_in_group("bale"):
		var rb := b as Node3D
		if rb == null or not is_instance_valid(rb):
			continue
		if not rb.has_meta("yard_origin"):
			continue   # not a yard-MM bale (forklift-placed elsewhere)
		# This bale is ALIVE and is about to be put back in its slot (pose snapped
		# + MultiMesh instance restored below), so re-adopt it: re-register it
		# under its slot key and lift the "consumed" mark for that slot only.
		# Slots whose bale no longer exists (fed into the line, burst open) are
		# NOT reached by this loop and stay consumed — clearing the whole set here
		# would refill them with invisible bodies, which is the C2 defect again.
		if rb.has_meta("slot_key"):
			var sk := String(rb.get_meta("slot_key"))
			_active_bale_rbs[sk] = rb
			_consumed_slots.erase(sk)
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
