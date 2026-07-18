extends Node3D

class_name NPCSpawner

# =============================================================================
# #195 — NPC roster data + spawner extracted from MainWorld.gd.
# =============================================================================
# Owns the NPC_DATA catalogue, the random-ring spawn placement around the
# player spawn marker, and the lift-booking registration so NPC operate
# planners can claim a mast lift at runtime.
#
# Pattern: child_node_manager. MainWorld instantiates one of these as a child
# node and calls setup(world, player_spawn_pos) followed by spawn_all() during
# world setup; the manager then materialises every NPC and returns the
# {npc_id: CharacterBody3D} dictionary that MainWorld stores in `npcs`.
# Spawned NPCs are still parented under MainWorld (not under this manager)
# so the resulting scene tree shape is identical to the pre-extract layout.

# ── NPC catalogue ─────────────────────────────────────────────────────────────
## #133 — operator spec. Per-NPC appearance overrides:
##   hair  : "short" (default), "mid", "bald"
##   cap   : if true, a dark-blue work cap replaces the hair on top of the head
##   beard : "none" (default), "thin", "thick"
##   hair_color: optional Color override (defaults to a variant-driven choice)
const NPC_DATA: Dictionary = {
	# #126 — per-NPC body proportions + facial-hair flavor. height_mul scales the
	# whole body in Y (0.85=short, 1.15=tall), width_mul scales torso/limbs in
	# X/Z (0.85=skinny, 1.20=heavyset). moustache/goatee are independent of
	# beard so you can have moustache-only or goatee-only.
	"romain":     {"name": "Romain",     "role": "shift_leader",       "color": Color.CYAN,             "appearance": {"height_mul": 1.0, "width_mul": 1.0, "moustache": true},
		"car": "res://src/scenes/vehicles/cars/HyundaiI20_2010.tscn"},
	"vincent":    {"name": "Vincent",    "role": "asst_shift_leader",  "color": Color.CORNFLOWER_BLUE,  "appearance": {"height_mul": 1.12, "width_mul": 0.88},
		"car": "res://src/scenes/vehicles/cars/VolvoV40Placeholder.tscn"},   # PLACEHOLDER: black Astra-as-Volvo until real GLB lands
	"pascal":     {"name": "Pascal",     "role": "extruder_op",        "color": Color.YELLOW,           "appearance": {"hair": "bald", "height_mul": 0.90, "width_mul": 1.15},
		"car": "res://src/scenes/vehicles/cars/FordKa2003.tscn"},   # Ford Ka 2003 — per-NPC Y-shrink 0.85 (body only) applied in _spawn_car_in_bay for "pascal"
	"kevin":      {"name": "Kevin",      "role": "extruder_op",        "color": Color.GREEN,            "appearance": {"cap": true, "hair_under_cap": true, "height_mul": 1.0, "width_mul": 1.0},
		"car": ""},   # not assigned a car yet
	"emrah":      {"name": "Emrah",      "role": "all_rounder",        "color": Color.WHITE,            "appearance": {"goatee": true, "height_mul": 1.13, "width_mul": 0.87},
		"car": "res://src/scenes/vehicles/cars/AudiA3Sportback.tscn"},
	"yassine":    {"name": "Yassine",    "role": "transitional",       "color": Color.LIGHT_GRAY,       "appearance": {"height_mul": 1.0, "width_mul": 0.95},
		"car": "passenger:player"},   # rides shotgun in the player's Swift
	"abdellilah": {"name": "Abdellilah", "role": "permanent_feeder",   "color": Color.ORANGE,           "appearance": {"cap": true, "hair_under_cap": true, "height_mul": 1.0, "width_mul": 1.05},
		"car": "res://src/scenes/vehicles/cars/FordKa2003.tscn"},
	"mohammed":   {"name": "Mohammed",   "role": "permanent_feeder",   "color": Color.TOMATO,           "appearance": {"beard": "full", "hair": "mid", "hair_color": Color(0.10, 0.07, 0.05), "height_mul": 1.0, "width_mul": 1.0},
		"car": "res://src/scenes/vehicles/cars/VWGolfMk6.tscn"},
	"peter":      {"name": "Peter",      "role": "production_manager", "color": Color.MEDIUM_ORCHID,    "appearance": {"height_mul": 0.98, "width_mul": 1.20},
		"car": "res://src/scenes/vehicles/cars/BMWX1Placeholder.tscn"},   # PLACEHOLDER: white AClass-as-BMW until real GLB lands
}

# Reference back to MainWorld for game_state / _shell / _on_floor / npcs /
# lift_booking and parenting spawned NPCs under the world. Set in _ready() and
# again in setup() so either call order works.
var _world : Node = null

# Player's actual spawn position this run — the random-ring anchor for NPC
# placement. Was previously WorldLayout.player_spawn read directly inside
# MainWorld; the spawner gets it once via setup() so it doesn't have to reach
# back into MainWorld for the value.
var _player_spawn_pos : Vector3 = Vector3.ZERO

# Local dictionary of spawned NPCs — also returned by spawn_all() so MainWorld
# can store it in its own `npcs` field for compatibility with the rest of the
# codebase that reads MainWorld.npcs directly.
var npcs : Dictionary = {}

func _ready() -> void:
	_world = get_parent()
	# Findable by MainWorld._spawn_mast_lift so the lift-booking step can call
	# back into _register_lifts_for_booking() after mast lifts spawn.
	if name == "" or name.begins_with("@"):
		name = "NPCSpawner"

# ── Public entry points ─────────────────────────────────────────────────────
func setup(world: Node, player_spawn_pos: Vector3) -> void:
	_world = world
	_player_spawn_pos = player_spawn_pos

func spawn_all() -> Dictionary:
	_spawn_npcs()
	# #147 Phase 3 / #148 Phase 4 — register every mast lift with the booking
	# registry so NPC operate planners can claim one when a target is too high
	# to reach from the floor. Called from MainWorld._spawn_mast_lift; left as
	# a no-op here so the spawner owns the full NPC lifecycle if a future
	# caller wants the convenience.
	return npcs

# =============================================================================
# NPCs
# =============================================================================
func _spawn_npcs() -> void:
	# Crew now spawns in a 2–20 m random ring around the PLAYER SPAWN marker, on
	# the OUTSIDE of the building (rejected if the candidate point lands inside
	# the shell's XZ AABB). The old NPCSpawnPoints markers / fallback dictionary
	# placed workers at hardcoded coordinates that didn't follow the player_spawn
	# the user calibrated in WorldSetup; in practice they appeared in the wrong
	# spot (often inside the building). Now they cluster naturally near where the
	# player starts the shift.
	if _world == null:
		_world = get_parent()
	var npc_script := load("res://src/scenes/world/NPC.gd")
	var humanoid_script := load("res://src/scenes/world/Humanoid.gd")
	var npc_variant := 0

	# Random-ring anchor — the PLAYER's actual spawn this run (set in
	# _spawn_player). Was WorldLayout.player_spawn, but that's the WorldSetup
	# marker, not where the player actually lands; a stale save or building
	# shift can put the actual player metres away from the marker.
	# #221-PC Phase 4 — prefer Plant.factory_center_scene() so NPCs centre on
	# the same building-centre every other layout-derived spawn uses. With
	# scene_origin = _get_factory_anchor() = _on_floor(_player_spawn_pos, 0),
	# this is the SAME XZ as _player_spawn_pos (just with Y = floor_top_y
	# baked in); the random ring then re-applies _on_floor anyway, so net
	# effect is identical to the legacy anchor. Migration is unification only.
	var anchor : Vector3 = _player_spawn_pos
	if _world.has_node("/root/Plant") and Plant.is_initialized():
		var fc : Vector3 = Plant.factory_center_scene()
		anchor = Vector3(fc.x, _player_spawn_pos.y, fc.z)
	# Building's XZ AABB so we can reject candidates that land INSIDE the shell.
	var shell := _world.call("_shell") as MeshInstance3D
	var bb_min := Vector2(INF, INF); var bb_max := Vector2(-INF, -INF)
	if shell and shell.mesh:
		var aabb := shell.global_transform * shell.mesh.get_aabb()
		bb_min = Vector2(aabb.position.x, aabb.position.z)
		bb_max = Vector2(aabb.position.x + aabb.size.x, aabb.position.z + aabb.size.z)

	var game_state = _world.get("game_state")
	var lift_booking = _world.get("lift_booking")

	for npc_id in NPC_DATA.keys():
		var data : Dictionary = NPC_DATA[npc_id]
		# #128 — the production manager works INSIDE the office on the operating
		# floor; field crew spawn OUTSIDE the building AABB. The role-flag below
		# inverts the containment check for `production_manager` so Peter ends
		# up at the indoor desk by design, not as a fall-through retry.
		var indoor_role : bool = String(data.get("role", "")) == "production_manager"
		var pos : Vector3 = anchor
		for attempt in 30:
			var ang : float = randf() * TAU
			var r   : float = randf_range(2.0, 20.0)
			var cand := anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			pos = cand
			var outside : bool = cand.x < bb_min.x or cand.x > bb_max.x \
				or cand.z < bb_min.y or cand.z > bb_max.y
			# Accept candidate when its INSIDE/OUTSIDE matches the role's
			# preference. Field crew want outside; the manager wants inside.
			if outside != indoor_role:
				break
		# Y from floor detection + 1 m for capsule centre.
		pos = _world.call("_on_floor", pos, 1.0)

		var npc := CharacterBody3D.new()
		npc.name = data["name"]

		# Blocky humanoid body (feet/legs/torso/arms/hands/head/face/hair) instead
		# of the old capsule pill. Its vertical centre sits at the node origin so
		# it lines up with the CapsuleShape3D collider below.
		# #186 — If the operator has customized this NPC, REPLACE the
		# NPC_DATA preset wholesale. The old merge-over-preset path silently
		# leaked default keys (cap, hair_under_cap, moustache, etc.) back in
		# whenever the operator hadn't explicitly toggled them off in the
		# customizer, so unsetting a flag was impossible. CharacterCustomizer
		# now guarantees a full appearance dict via _ensure_defaults() before
		# save, so the REPLACE is safe.
		var npc_ap : Dictionary = data.get("appearance", {}).duplicate(true)
		if game_state and "npc_appearances" in game_state:
			var custom_npc_ap = game_state.get("npc_appearances")
			if custom_npc_ap is Dictionary and custom_npc_ap.has(npc_id):
				var saved_ap = custom_npc_ap[npc_id]
				if saved_ap is Dictionary and not (saved_ap as Dictionary).is_empty():
					npc_ap = (saved_ap as Dictionary).duplicate(true)
		var body : Node3D = humanoid_script.build(data["color"], npc_variant, npc_ap)
		body.name = "HumanoidBody"           # tagged so NPC._physics_process can scale it for crouch / prone (#146)
		npc_variant += 1
		npc.add_child(body)

		var col := CollisionShape3D.new()
		col.name = "BodyCollision"           # tagged so NPC can resize the capsule for crouch / prone (#146)
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.8
		col.shape  = cap
		npc.add_child(col)

		if npc_script:
			npc.set_script(npc_script)

		npc.set_meta("map_color", data["color"])   # MapOverlay draws crew in this colour

		_world.add_child(npc)
		npc.global_position = pos
		# #147 / #148 — hand the lift booking to every NPC so the operate planner
		# can claim a mast lift when its target is too high to reach from the
		# floor. Null until _register_lifts_for_booking has run; the planner
		# guards against that case.
		if lift_booking != null:
			npc.set("lift_booking", lift_booking)
		npcs[npc_id] = npc

## Walk the scene tree, build a LiftBooking, register every mast lift instance.
## Called after _spawn_mast_lift; the booking is then handed to every NPC during
## _spawn_crew_manager so the planner can claim lifts at runtime.
func _register_lifts_for_booking() -> void:
	if _world == null:
		_world = get_parent()
	var lift_booking = _world.get("lift_booking")
	if lift_booking == null:
		lift_booking = LiftBooking.new()
		lift_booking.name = "LiftBooking"
		_world.add_child(lift_booking)
		_world.set("lift_booking", lift_booking)
	var count : int = 0
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v != null and String(v.get("vehicle_type")) == "mast_lift":
			lift_booking.register_lift(v)
			count += 1
	# Some MastLift instances may not be in the "vehicle" group (depends on the
	# .tscn). Fallback: find by class.
	if count == 0:
		for v in _world.find_children("", "VehicleBody3D", true, false):
			if v != null and String(v.get("vehicle_type")) == "mast_lift":
				lift_booking.register_lift(v)
				count += 1
	print("[NPCSpawner] LiftBooking: registered %d mast lift(s)" % count)
	# NPCs spawn BEFORE mast lifts in _ready order, so the booking ref they got
	# was null. Backfill it now so the operate planner can claim a lift on its
	# next tick.
	for npc_id in npcs.keys():
		var npc = npcs[npc_id]
		if npc != null and is_instance_valid(npc):
			npc.set("lift_booking", lift_booking)

# ── Public accessors ────────────────────────────────────────────────────────
func get_npc(npc_id: String) -> Node:
	return npcs.get(npc_id, null)

func get_all_npcs() -> Array:
	return npcs.values()
