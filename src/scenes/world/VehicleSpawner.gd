extends Node3D

class_name VehicleSpawner

# =============================================================================
# #195 follow-up — Vehicle spawning extracted from MainWorld.gd.
# =============================================================================
# Owns the per-vehicle spawn helpers (forklift / bale clamp / mast lift) plus
# the shared `spawn_vehicle_instances` helper they all delegate to. MainWorld
# instantiates one of these as a child node and calls setup(world, spawn_pos);
# the spawner then materialises every vehicle from WorldLayout (or a hardcoded
# fallback offset when the operator hasn't placed any in WorldSetup).
#
# Spawned vehicles are still parented under MainWorld (not under this manager),
# so the resulting scene tree shape is identical to the pre-extract layout.
# Mirrors ExteriorManager's child-node-manager pattern.

# Reference back to MainWorld for canonical helpers + spawned-node parenting.
# Set when the manager is added to the tree (its parent IS MainWorld) and again
# in setup() so the public API is safe to call from the integration callsite.
var _world : Node = null

# Cached at setup time — the player's actual spawn position, used by some
# fallback paths (currently routed through _world helpers, but kept on the
# manager so future call-sites can avoid the extra hop).
var _player_spawn_pos : Vector3 = Vector3.ZERO

var lift_booking: Node = null

# ── De-nest state for ONE spawn pass ────────────────────────────────────────
# A vehicle added this frame is not in the physics space yet, so a shape query
# cannot see it: two vehicles spawned in the same pass would both read "clear"
# and materialise inside each other. They are resolved GEOMETRICALLY against
# this list instead — the same split BuildMode._denest_loaded_vehicles uses for
# a restored save (live probe for the already-synced world, settled list for
# this pass).
#
# Both lists deliberately span every spawn_vehicle_instances call, because
# MainWorld._spawn_merlo calls back into this same instance after setup(): a
# Merlo must not land inside a mast lift placed two calls earlier.
#
# Entries are {"pos": Vector3, "rot": float, "size": Vector3} where size is
# PRE-INFLATED (see _spawn_blocker) so BuildMode's 85 % shrink lands on the
# real hull.
var _settled_hulls : Array[Dictionary] = []
# Every vehicle this pass added, excluded from the live probe for the same
# not-yet-synced reason (it would otherwise be reported at a stale pose).
var _pass_vehicles : Array[Node] = []
# One warning per pass, not one per vehicle, when BuildMode is unreachable.
var _denest_unavailable_warned : bool = false

func _ready() -> void:
	if _world == null:
		_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
# Mirrors the integration call from MainWorld._spawn_world_items:
#   var veh_spawner := VehicleSpawner.new(); add_child(veh_spawner)
#   veh_spawner.setup(self, _player_spawn_pos)
func setup(world: Node, player_spawn_pos: Vector3) -> void:
	_world = world
	_player_spawn_pos = player_spawn_pos
	spawn_forklift()
	spawn_bale_clamp()
	spawn_mast_lift()

# =============================================================================
# VEHICLES — the user can place N of each in WorldSetup; we instantiate one
# scene per saved position, falling back to a single hardcoded "next to player"
# slot if WorldLayout has no spawns for that vehicle id.
# =============================================================================

## Common helper: spawn instances of `scene_path` at every WorldLayout position
## under `layout_id`. If the user hasn't placed any, fall back to a single
## instance at `fallback_offset` from the factory anchor.
## Kept PUBLIC because MainWorld._spawn_merlo (which stays in MainWorld) calls
## back into here for the Merlo + Merlo P40 spawn pair.
##
## #221-PC Phase 3 — when Plant is initialized + WorldLayout has PC data, this
## reads from WorldLayout.vehicle_spawns_pc and routes through Plant. When PC
## data isn't available (very first boot before migrate_to_pc runs, or sandbox/
## test scenes without Plant), falls back to the legacy _layout_to_scene path.
## Both paths are mathematically equivalent for already-saved layouts; the PC
## path also applies world_yaw to the fallback offset, fixing the long-standing
## "fallback spawns along world +X regardless of building rotation" bug.
func spawn_vehicle_instances(layout_id: String, scene_path: String, fallback_offset: Vector3, label: String) -> void:
	var scn := load(scene_path) as PackedScene
	if scn == null:
		push_warning("[VehicleSpawner] %s missing — skipping" % scene_path); return

	# Decide which coord system this run uses. We pick once per call so all
	# instances of the same vehicle share the same path (no mid-loop flip).
	var use_pc : bool = _world.has_node("/root/Plant") and Plant.is_initialized() and WorldLayout.has_pc_data
	var floor_y : float = _world.call("_floor_top_y")

	# ── Fallback branch (no operator-placed markers for this id) ─────────────
	var positions : Array = WorldLayout.get_vehicle_spawns(layout_id)
	if positions.is_empty():
		var pos : Vector3
		if use_pc:
			# fallback_offset is a scene-metre-relative-to-anchor offset
			# (e.g. (3,0,0) = "3 m east of factory anchor"). Convert to PC by
			# adding to PC_CENTER. pc_to_scene then applies world_yaw — so a
			# rotated building rotates the fallback vehicle with it. The old
			# path skipped that yaw, leaving fallback vehicles in world-X
			# alignment regardless of building rotation.
			var pc : Vector2 = Plant.PC_CENTER + Vector2(fallback_offset.x, fallback_offset.z)
			pos = Plant.pc_to_scene_with_y(pc, floor_y + 0.5)
		else:
			var anchor : Vector3 = _world.call("_get_factory_anchor")
			pos = _world.call("_on_floor", anchor + fallback_offset, 0.5)
		var v := scn.instantiate()
		_world.add_child(v)
		var v3 := v as Node3D
		if v3 != null:
			pos = _denest_spawn(v3, _catalog_id_for_scene(scene_path), pos, label, 1)
			v3.global_position = pos
		print("[VehicleSpawner] %s (fallback%s) spawned at %s" % [
			label, " PC" if use_pc else "", str(pos)])
		return

	# ── Canonical branch — every operator-placed marker becomes a spawn ──────
	# Read PC-parallel array when available; index in lockstep with the legacy
	# positions array (migrate_to_pc preserves order). When PC data is absent,
	# walk the legacy Vector3 list through _layout_to_scene exactly as before.
	var positions_pc : Array = []
	if use_pc and WorldLayout.vehicle_spawns_pc.has(layout_id):
		positions_pc = WorldLayout.vehicle_spawns_pc[layout_id]
	# Treat "PC array length disagrees with legacy" as a soft fault — fall back
	# to legacy for the whole call so we never mismatch a marker to the wrong
	# vehicle. Reproduces only if migrate_to_pc was interrupted mid-walk.
	if use_pc and positions_pc.size() != positions.size():
		push_warning("[VehicleSpawner] %s: PC array size %d ≠ legacy %d — using legacy path" % [
			layout_id, positions_pc.size(), positions.size()])
		use_pc = false

	for i in positions.size():
		var rel : Vector3 = positions[i]
		if not bool(_world.call("_layout_rel_sane", rel)):
			push_warning("[VehicleSpawner] %s #%d marker is %.0f m from the anchor — corrupt layout data, skipping (re-place it in world_layout.json; WorldSetup was deleted 2026-08-17)" \
				% [label, i + 1, Vector2(rel.x, rel.z).length()])
			continue
		var p : Vector3
		if use_pc:
			p = Plant.pc_to_scene_with_y(positions_pc[i], floor_y + 0.5)
		else:
			var scene_pos : Vector3 = _world.call("_layout_to_scene", rel)
			p = _world.call("_on_floor", scene_pos, 0.5)
		var v := scn.instantiate()
		_world.add_child(v)
		var v3 := v as Node3D
		if v3 != null:
			p = _denest_spawn(v3, _catalog_id_for_scene(scene_path), p, label, i + 1)
			v3.global_position = p
		print("[VehicleSpawner] %s #%d %s placed at scene(%.1f,%.1f)" % [
			label, i + 1, "PC" if use_pc else "legacy", p.x, p.z])

# =============================================================================
# SPAWN DE-NEST — measured 2026-07-21 (test_spawn_clearance, NOLINE config).
# =============================================================================
# The operator's three mast_lift markers sit 1.35 / 1.64 / 2.97 m apart, which is
# narrower than a mast-lift hull, so lifts #2 and #3 materialised INSIDE #1 (70.9 %
# and 33.4 % hull penetration). Before commit 9334310 those three sat nested in an
# empty field 200 m off the plant where nobody met them; on the marker-frame fix
# they arrive nested ON the operating floor. Overlap is also the entry condition
# for the runaway contact-recovery drift fixed in 276d142/5a56d68.
#
# The correction is RUNTIME-ONLY. world_layout.json is the operator's site survey;
# nothing here rewrites it, and the warning says so, so a nudged vehicle can never
# be mistaken for the pose he authored.

## Pose `v` should actually spawn at: `at` when it is clear, otherwise the first
## clear spot on BuildMode's de-nest ring search. A vehicle is NEVER dropped — if
## the whole search is blocked, `at` is returned and the conflict is reported.
func _denest_spawn(v: Node3D, catalog_id: String, at: Vector3, label: String, idx: int) -> Vector3:
	var rot_y : float = v.rotation.y
	# Pre-inflated once here so the gate size and every settled entry agree.
	var size := _hull_footprint(v) / 0.85
	# Self goes in the skip list BEFORE the first probe: `v` is already a child of
	# the world, so if the space ever did sync it mid-pass it would report itself
	# and every vehicle would be nudged off its own marker for nothing.
	_pass_vehicles.append(v)
	var blocker := _blocker_name(_spawn_blocker(catalog_id, at, rot_y, size))
	if blocker == "":
		_settled_hulls.append({"pos": at, "rot": rot_y, "size": size})
		return at
	# Same step / ring count / angle count as BuildMode's load-path de-nest, so
	# both paths resolve an identical world to an identical layout and the
	# regression harness stays reproducible.
	for ring in range(1, BuildMode.DENEST_RINGS + 1):
		var radius := float(ring) * BuildMode.DENEST_STEP_M
		for a in BuildMode.DENEST_ANGLES:
			var ang := TAU * float(a) / float(BuildMode.DENEST_ANGLES)
			var cand := at + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
			if _spawn_blocker(catalog_id, cand, rot_y, size) != "":
				continue
			push_warning("[VehicleSpawner] de-nest at spawn: %s #%d would materialise inside '%s' at scene(%.1f, %.1f) — RUNTIME pose offset %.2f m to scene(%.1f, %.1f). The marker in world_layout.json is UNCHANGED; edit world_layout.json to make this permanent (WorldSetup was deleted 2026-08-17)."
				% [label, idx, blocker, at.x, at.z, (cand - at).length(), cand.x, cand.z])
			_settled_hulls.append({"pos": cand, "rot": rot_y, "size": size})
			return cand
	push_warning("[VehicleSpawner] de-nest at spawn: %s #%d is inside '%s' at scene(%.1f, %.1f) and NO clear spot was found within %.1f m — spawned ON its marker anyway (never dropped). Re-place the marker in world_layout.json (WorldSetup was deleted 2026-08-17)."
		% [label, idx, blocker, at.x, at.z, float(BuildMode.DENEST_RINGS) * BuildMode.DENEST_STEP_M])
	_settled_hulls.append({"pos": at, "rot": rot_y, "size": size})
	return at

## Resolve BuildMode's settled-list placeholder into the real node name.
## _denest_blocker reports a geometric hit as "restored vehicle #N", N indexing
## the settled array it was handed — here that array is _settled_hulls, which is
## appended in lockstep with _pass_vehicles, so N names a vehicle THIS pass
## spawned. Left verbatim the warning would be unreadable to the operator.
func _blocker_name(raw: String) -> String:
	const PREFIX := "restored vehicle #"
	if not raw.begins_with(PREFIX):
		return raw
	var idx := raw.substr(PREFIX.length()).to_int()
	if idx < 0 or idx >= _pass_vehicles.size():
		return raw
	var other : Node = _pass_vehicles[idx]
	if other == null or not is_instance_valid(other):
		return raw
	return String(other.name)

## Name of whatever blocks `at`, or "" when it is clear. Delegates to BuildMode's
## _denest_blocker so there is exactly ONE definition of "two vehicles overlap"
## in the codebase; without BuildMode there is no probe and the pass is skipped
## loudly rather than silently.
func _spawn_blocker(catalog_id: String, at: Vector3, rot_y: float, size: Vector3) -> String:
	var bm : Variant = _world.get("build_mode")
	if not (bm is Node) or not is_instance_valid(bm as Node):
		if not _denest_unavailable_warned:
			_denest_unavailable_warned = true
			push_warning("[VehicleSpawner] BuildMode unreachable — spawn de-nest SKIPPED this pass; overlapping markers will spawn overlapping hulls.")
		return ""
	return String((bm as Node).call("_denest_blocker",
		catalog_id, at, rot_y, size, _settled_hulls, _pass_vehicles))

## Real collision footprint of a vehicle, in its own local frame.
## Measured from the actual CollisionShape3D set rather than read from the
## catalog because the two disagree — MastLift's chassis hull is 1.5 m wide, its
## catalog entry says 1.4 — and test_spawn_clearance scores the REAL hulls. A
## catalog-sized gate would call a 0.1 m interpenetration "clear" and leave the
## guard red. Area3D volumes (VehicleEnterArea) are triggers, not hulls.
func _hull_footprint(v: Node3D) -> Vector3:
	var acc := AABB()
	var have := false
	var to_local := v.global_transform.affine_inverse()
	for n in v.find_children("", "CollisionShape3D", true, false):
		var cs := n as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var body := _collision_owner(cs)
		if body == null or body is Area3D:
			continue
		var box : AABB = (to_local * cs.global_transform) * cs.shape.get_debug_mesh().get_aabb()
		acc = box if not have else acc.merge(box)
		have = true
	if not have:
		# No hull to measure (a purely visual vehicle): let BuildMode's own
		# catalog fallback decide, un-inflated by the caller's /0.85.
		return Vector3(2.0, 2.5, 4.0) * 0.85
	return acc.size

## Nearest CollisionObject3D ancestor of a shape node, or null.
func _collision_owner(cs: Node) -> CollisionObject3D:
	var cur : Node = cs.get_parent()
	while cur != null:
		if cur is CollisionObject3D:
			return cur as CollisionObject3D
		cur = cur.get_parent()
	return null

## Catalog id whose "scene" is `scene_path`. Layout ids ("bale_clamp") and catalog
## ids ("vehicle_baleclamp") share no naming rule, so the scene path is the only
## reliable join. "" when the vehicle has no catalog entry — BuildMode's live
## probe then uses its documented default hull size.
func _catalog_id_for_scene(scene_path: String) -> String:
	for item in PlaceableCatalog.items():
		if String(item.get("scene", "")) == scene_path:
			return String(item.get("id", ""))
	return ""

func spawn_forklift() -> void:
	spawn_vehicle_instances("forklift", "res://src/scenes/vehicles/Forklift.tscn",
		Vector3(3.0, 0.0, 0.0), "Forklift")

## Anchor for the vehicle row — the player's actual spawn (marker OR resumed save),
## so every vehicle parks beside the player wherever they end up.
## Public so MainWorld._spawn_lpg_rack (which stays in MainWorld) can still reach
## the same anchor it always used.
func vehicle_anchor() -> Vector3:
	return _world.call("_get_factory_anchor")

func spawn_bale_clamp() -> void:
	spawn_vehicle_instances("bale_clamp", "res://src/scenes/vehicles/BaleClamp.tscn",
		Vector3(10.0, 0.0, 0.0), "Bale clamp")

func spawn_mast_lift() -> void:
	spawn_vehicle_instances("mast_lift", "res://src/scenes/vehicles/MastLift.tscn",
		Vector3(20.0, 0.0, 0.0), "Mast lift")
	_register_lifts_for_booking()

func _register_lifts_for_booking() -> void:
	if lift_booking == null:
		lift_booking = LiftBooking.new()
		lift_booking.name = "LiftBooking"
		_world.add_child(lift_booking)

	var count : int = 0
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v != null and String(v.get("vehicle_type")) == "mast_lift":
			lift_booking.register_lift(v)
			count += 1

	if count == 0:
		for v in _world.find_children("", "VehicleBody3D", true, false):
			if v != null and String(v.get("vehicle_type")) == "mast_lift":
				lift_booking.register_lift(v)
				count += 1

	print("[VehicleSpawner] LiftBooking: registered %d mast lift(s)" % count)

	for npc_id in _world.npcs.keys():
		var npc = _world.npcs[npc_id]
		if npc != null and is_instance_valid(npc):
			npc.set("lift_booking", lift_booking)
