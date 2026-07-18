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
		_world.add_child(v); v.global_position = pos
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
			push_warning("[VehicleSpawner] %s #%d marker is %.0f m from the anchor — corrupt layout data, skipping (re-place it in WorldSetup)" \
				% [label, i + 1, Vector2(rel.x, rel.z).length()])
			continue
		var p : Vector3
		if use_pc:
			p = Plant.pc_to_scene_with_y(positions_pc[i], floor_y + 0.5)
		else:
			var scene_pos : Vector3 = _world.call("_layout_to_scene", rel)
			p = _world.call("_on_floor", scene_pos, 0.5)
		var v := scn.instantiate()
		_world.add_child(v); v.global_position = p
		print("[VehicleSpawner] %s #%d %s placed at scene(%.1f,%.1f)" % [
			label, i + 1, "PC" if use_pc else "legacy", p.x, p.z])

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
