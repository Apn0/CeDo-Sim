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
func spawn_vehicle_instances(layout_id: String, scene_path: String, fallback_offset: Vector3, label: String) -> void:
	var scn := load(scene_path) as PackedScene
	if scn == null:
		push_warning("[VehicleSpawner] %s missing — skipping" % scene_path); return
	var positions : Array = WorldLayout.get_vehicle_spawns(layout_id)
	if positions.is_empty():
		# Fallback: spawn one next to the factory anchor.
		var anchor : Vector3 = _world.call("_get_factory_anchor")
		var pos : Vector3 = _world.call("_on_floor", anchor + fallback_offset, 0.5)
		var v := scn.instantiate()
		_world.add_child(v); v.global_position = pos
		print("[VehicleSpawner] %s (fallback) spawned at %s" % [label, str(pos)])
		return
	# Markers are stored as player_spawn-relative offsets in north-up RD space.
	# _layout_to_scene() rotates them by the floor-plan calibration angle (the
	# RD→building rotation) and anchors them at the player's scene position.
	for i in positions.size():
		var rel : Vector3 = positions[i]
		if not bool(_world.call("_layout_rel_sane", rel)):
			push_warning("[VehicleSpawner] %s #%d marker is %.0f m from the anchor — corrupt layout data, skipping (re-place it in WorldSetup)" \
				% [label, i + 1, Vector2(rel.x, rel.z).length()])
			continue
		var scene_pos : Vector3 = _world.call("_layout_to_scene", rel)
		var p : Vector3 = _world.call("_on_floor", scene_pos, 0.5)
		var v := scn.instantiate()
		_world.add_child(v); v.global_position = p
		print("[VehicleSpawner] %s #%d  placed at scene(%.1f,%.1f)" % [
			label, i + 1, p.x, p.z])

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
	# #147 Phase 3 / #148 Phase 4 — register every mast lift with the booking
	# registry so NPC operate planners can claim one when a target is too high
	# to reach from the floor. Created lazily so non-mast-lift worlds skip it.
	_world.call("_register_lifts_for_booking")
