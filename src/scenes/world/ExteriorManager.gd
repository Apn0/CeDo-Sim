extends Node3D

class_name ExteriorManager

# =============================================================================
# #192 follow-up — Exterior layout extracted from MainWorld.gd.
# =============================================================================
# Owns the road extensions / perimeter fence / sidewalk + crosswalk + road
# markings / trees / power poles / transformer / neighbour buildings around
# the plant. MainWorld instantiates one of these as a child node and calls
# build_exterior(anchor, ground_y) exactly once during world setup; the
# manager then materialises everything from the constants block below.
#
# All offsets are in BUILDING-LOCAL space (X right of the right wall, Z along
# its length) so we can re-skin the building yaw without touching numbers
# throughout the file — only _bo()/_world_yaw() out of MainWorld rotate them.
# Spawned nodes are still parented under MainWorld (not under this manager),
# so the resulting scene tree shape is identical to the pre-extract layout.

# ── Building-local offset tables (item 4: pull magic numbers to constants) ──
# Roads. Each entry is [start_offset, end_offset] in metres, B-local.
const ROAD_SOUTH_EXT       : Array = [Vector3(-42.0, 0.0, -40.0), Vector3(  5.0, 0.0, -40.0)]
const ROAD_EAST_SERVICE    : Array = [Vector3( 35.0, 0.0, -30.0), Vector3( 35.0, 0.0,  20.0)]
# 2026-07-06 — re-georeferenced against the parametric shell. The old
# constants predate the survey georeference: both road extensions and
# FENCE_NORTH converted to positions INSIDE the building (operator
# screenshots: road + fence crossing the factory interior). All offsets are
# anchor-local (PC - 500), rotated by the canonical yaw at spawn time.
const ROAD_NORTH_BALE_YARD : Array = [Vector3(-49.0, 0.0,  55.4), Vector3(-73.2, 0.0,  58.1)]
const ROAD_INTERNAL_AISLE  : Array = [Vector3(-77.9, 0.0,  19.5), Vector3(-97.2, 0.0,  42.5)]

# Perimeter fence runs: NW long side, NE end, half of the SE side — the
# south stays open for the bale lot and the access road.
const FENCE_NORTH      : Array = [Vector3(  7.1, 0.0, -105.1), Vector3(-124.7, 0.0,  52.0)]
const FENCE_EAST       : Array = [Vector3( 99.0, 0.0,  -27.9), Vector3(   7.1, 0.0, -105.1)]
const FENCE_SOUTH_EAST : Array = [Vector3( 99.0, 0.0,  -27.9), Vector3(  41.1, 0.0,  41.0)]

# Gate barrier at the south plant entry.
const GATE_OFFSET : Vector3 = Vector3(0.0, 0.0, 25.0)

# Sidewalk hugging the local-west side of De Asselen Kuil.
const SIDEWALK_PATH : Array = [Vector3(-45.0, 0.0, -40.0), Vector3(-45.0, 0.0, 20.0)]

# Crosswalk at the bend where the road turns east.
const CROSSWALK_OFFSET     : Vector3 = Vector3(-42.0, 0.0, 0.0)
const CROSSWALK_STRIPE_QTY : int = 6

# Road markings (kind, B-local offset). Yaw + colour are uniform.
const ROAD_MARKINGS : Array = [
	["stop_text",         Vector3(  0.0, 0.0, 22.0)],
	["give_way_triangle", Vector3(  0.0, 0.0, 19.0)],
	["give_way_triangle", Vector3(  2.0, 0.0, 19.0)],
	["arrow_straight",    Vector3(-25.0, 0.0,  5.0)],
	["arrow_straight",    Vector3(-25.0, 0.0, 11.0)],
]

# Tree clusters spaced along the local-west side of De Asselen Kuil.
const TREE_OFFSETS : Array = [
	Vector3(-50.0, 0.0, -30.0),
	Vector3(-50.0, 0.0, -10.0),
	Vector3(-50.0, 0.0,  10.0),
	Vector3(-50.0, 0.0,  28.0),
]
const TREE_RADIUS : float = 3.5
const TREE_COUNT  : int   = 5

# Power poles + wires. PowerPole.build_pole() places insulators along local +X.
const POWER_POLE_OFFSETS : Array = [
	Vector3(-46.0, 0.0, -38.0),
	Vector3(-46.0, 0.0, -10.0),
	Vector3(-46.0, 0.0,  18.0),
	Vector3(-30.0, 0.0,  33.0),
	Vector3(  0.0, 0.0,  33.0),
]

# Transformer cabinet in the south yard.
const TRANSFORMER_OFFSET : Vector3 = Vector3(10.0, 0.0, -10.0)

# Neighbour buildings. [offset, size, body_colour, sign_text, sign_colour, seed].
const NEIGHBOR_SW : Dictionary = {
	"offset": Vector3(-60.0, 0.0, -55.0),
	"size":   Vector3( 18.0, 6.0,  14.0),
	"body":   Color(0.82, 0.78, 0.70),
	"text":   "Recyclepartner BV",
	"sign":   Color(0.18, 0.22, 0.36),
	"seed":   11,
}
const NEIGHBOR_NW : Dictionary = {
	"offset": Vector3(-55.0, 0.0,  25.0),
	"size":   Vector3( 12.0, 4.5,  10.0),
	"body":   Color(0.74, 0.70, 0.62),
	"text":   "Werkplaats",
	"sign":   Color(0.20, 0.18, 0.18),
	"seed":   23,
}

# Preload the exterior placeable scripts once so each build call doesn't pay
# the load cost again. The paths are stable; if any move, fix here.
const _ROAD_SCRIPT        := preload("res://src/scenes/world/Road.gd")
const _FENCE_SCRIPT       := preload("res://src/scenes/world/exterior/ChainLinkFence.gd")
const _GATE_SCRIPT        := preload("res://src/scenes/world/exterior/GateBarrier.gd")
const _SIDEWALK_SCRIPT    := preload("res://src/scenes/world/exterior/Sidewalk.gd")
const _CROSSWALK_SCRIPT   := preload("res://src/scenes/world/exterior/Crosswalk.gd")
const _MARKING_SCRIPT     := preload("res://src/scenes/world/exterior/RoadMarking.gd")
const _TREE_SCRIPT        := preload("res://src/scenes/world/exterior/TreeCluster.gd")
const _POLE_SCRIPT        := preload("res://src/scenes/world/exterior/PowerPole.gd")
const _TRANSFORMER_SCRIPT := preload("res://src/scenes/world/exterior/TransformerCabinet.gd")
const _NEIGHBOR_SCRIPT    := preload("res://src/scenes/world/exterior/NeighborBuilding.gd")

# Reference back to MainWorld for _bo / _world_yaw / spawned-node parenting.
# Set when the manager is added to the tree (its parent IS MainWorld).
var _world : Node = null

func _ready() -> void:
	_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
func build_exterior(anchor: Vector3, ground_y: float) -> void:
	if _world == null:
		_world = get_parent()
	_spawn_road_extensions(anchor, ground_y)
	_spawn_perimeter_fence(anchor, ground_y)
	_spawn_exterior_props(anchor, ground_y)

# ── Helpers that defer to MainWorld's canonical yaw / bo math ───────────────
func _bo(ga: Vector3, offset: Vector3) -> Vector3:
	return _world.call("_bo", ga, offset)

func _world_yaw() -> float:
	return _world.call("_world_yaw")

# #199 — Per-item ground Y sampling. The old build_exterior assumed a single
# flat ground_y across the whole plant footprint, which is fine on the bare
# exterior_ground plane but flat-out wrong on top of an OSM/PDOK terrain
# where the woods, road shoulder and bale-yard plinths all sit at different
# elevations. Fences, poles and trees that share one Y end up floating over
# dips (woods area) or buried in mounds.
#
# Casts a 200 m vertical ray at the requested XZ. Hits the first body with
# collision — exterior_ground, terrain.glb, road decks, bale-yard fills,
# whatever's there. Returns the hit Y; fall back to `fallback_y` if nothing
# was hit (e.g. the XZ is over the void).
func _sample_ground_y(world_xz: Vector3, fallback_y: float) -> float:
	if _world == null:
		return fallback_y
	var w3d := (_world as Node3D).get_world_3d() if _world is Node3D else null
	if w3d == null:
		return fallback_y
	var space : PhysicsDirectSpaceState3D = w3d.direct_space_state
	if space == null:
		return fallback_y
	var from := Vector3(world_xz.x, fallback_y + 200.0, world_xz.z)
	var to   := Vector3(world_xz.x, fallback_y - 200.0, world_xz.z)
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return fallback_y
	return float((hit["position"] as Vector3).y)

## Rotates `offset` through the world yaw, adds it to `ga` (anchor at the plant-
## floor Y), AND OVERRIDES the Y with the ground sampled at the resulting XZ.
## Use this in place of `_bo()` for items that need to plant on real terrain
## (fence posts, poles, trees) instead of riding the fixed plant-floor plane.
func _bo_grounded(ga: Vector3, offset: Vector3) -> Vector3:
	var p : Vector3 = _bo(ga, offset)
	p.y = _sample_ground_y(p, ga.y)
	return p

# ── Road network branches (south ext, east service, north access, aisle) ────
func _spawn_road_extensions(anchor: Vector3, ground_y: float) -> void:
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	var segments : Array = [
		{"name": "DeAsselenKuil_SouthExt",  "pts": ROAD_SOUTH_EXT},
		{"name": "EastServiceRoad",         "pts": ROAD_EAST_SERVICE},
		{"name": "NorthBaleYardAccess",     "pts": ROAD_NORTH_BALE_YARD},
		{"name": "InternalPlantAisle",      "pts": ROAD_INTERNAL_AISLE},
	]
	for seg in segments:
		var r : Road = _ROAD_SCRIPT.new()
		r.name = seg["name"]
		r.surface_y = ground_y
		var pts : Array = seg["pts"]
		r.setup([_bo(ga, pts[0]), _bo(ga, pts[1])])
		_world.add_child(r)
	print("[ExteriorManager] Road extensions: %d extra segments (south ext / east service / north access / plant aisle)" \
		% segments.size())

# ── Perimeter fence + south entry gate ──────────────────────────────────────
func _spawn_perimeter_fence(anchor: Vector3, ground_y: float) -> void:
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	var _by : float = _world_yaw()
	var perimeters : Array = [
		{"name": "PerimeterFence_North",     "pts": FENCE_NORTH},
		{"name": "PerimeterFence_East",      "pts": FENCE_EAST},
		{"name": "PerimeterFence_SouthEast", "pts": FENCE_SOUTH_EAST},
	]
	for p in perimeters:
		var f = _FENCE_SCRIPT.new()
		f.name = p["name"]
		# setup() must come BEFORE add_child so _ready() sees populated waypoints.
		# #199 — each endpoint Y is sampled from the actual ground at its XZ, so
		# a fence that crosses a dip (woods) follows the terrain instead of
		# floating at the plant-floor plane.
		var pts : Array = p["pts"]
		f.setup([_bo_grounded(ga, pts[0]), _bo_grounded(ga, pts[1])])
		_world.add_child(f)
	# Per operator: no automatic boom barrier at the plant entry. The real
	# CeDo gate is a manual roller, not an auto-boom; the barrier here was
	# scaffolding from before that requirement was clear, and it ended up
	# stuck closed forever because no gate-logic was ever wired (the comment
	# at this site read "set_open(true) when gate logic wires up", which
	# never happened). Removing it also unblocks fence-line vaulting along
	# the entry stretch where the gate's collision footprint overlapped.
	#
	# If a manual entry placeable is later wanted, drop a `gate_roller` from
	# the build catalog instead — that one is operator-spec'd and toggles
	# correctly.
	print("[ExteriorManager] Perimeter fence: %d runs (entry gate intentionally not spawned)" % perimeters.size())

# ── Sidewalk, crosswalk, markings, trees, power line, transformer, neighbors ─
func _spawn_exterior_props(anchor: Vector3, ground_y: float) -> void:
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	var by : float = _world_yaw()
	# Sidewalk.
	var sidewalk = _SIDEWALK_SCRIPT.new()
	sidewalk.name = "Sidewalk_DeAsselenKuil"
	sidewalk.surface_y = ground_y
	# setup() BEFORE add_child so _ready() sees populated waypoints.
	sidewalk.setup([_bo(ga, SIDEWALK_PATH[0]), _bo(ga, SIDEWALK_PATH[1])])
	_world.add_child(sidewalk)
	# Crosswalk. Y comes from global_position; surface_y=0 keeps stripes flush.
	var crosswalk = _CROSSWALK_SCRIPT.new()
	crosswalk.name = "Crosswalk_DeAsselenKuil"
	crosswalk.surface_y = 0.0
	crosswalk.setup(CROSSWALK_STRIPE_QTY)
	_world.add_child(crosswalk)
	crosswalk.global_position = _bo(ga, CROSSWALK_OFFSET)
	crosswalk.rotation.y = by
	# Road markings — STOP + give-ways at the gate, arrows in the parking aisles.
	var markings = _MARKING_SCRIPT.new()
	markings.name = "RoadMarkings"
	markings.surface_y = ground_y
	_world.add_child(markings)
	for m in ROAD_MARKINGS:
		markings.build_at(m[0] as String, _bo(ga, m[1] as Vector3), by, "white")
	# Tree clusters along the west road shoulder. #199 — sample the ground at
	# each cluster centre so trees plant on real terrain (the road shoulder is
	# slightly lower than the plant floor in the OSM/PDOK strip).
	for i in TREE_OFFSETS.size():
		var tc = _TREE_SCRIPT.new()
		tc.name = "TreeCluster_%d" % i
		_world.add_child(tc)
		tc.cluster_at(_bo_grounded(ga, TREE_OFFSETS[i]), TREE_RADIUS, TREE_COUNT, i * 17 + 3)
	# Power poles with wires strung between consecutive poles. #199 — each pole
	# samples its own ground; wires between them then connect at their real
	# crossarm heights (which is what gives the line its visible droop).
	var pole_positions : Array = []
	for offset in POWER_POLE_OFFSETS:
		pole_positions.append(_bo_grounded(ga, offset))
	var poles : Array = []
	for i in pole_positions.size():
		var pp = _POLE_SCRIPT.new()
		pp.name = "PowerPole_%d" % i
		_world.add_child(pp)
		pp.global_position = pole_positions[i]
		# Apply world yaw so the pole's local +X crossarm aligns with the rotated
		# frame — wires emerge from insulator tips at the correct run angle.
		pp.rotation.y = by
		pp.build_pole()
		poles.append(pp)
	for i in poles.size() - 1:
		poles[i].build_to(pole_positions[i + 1])
	# Transformer cabinet — also gets the ground sample so the box sits on the
	# yard surface, not floating in air over the south plinth.
	var transformer = _TRANSFORMER_SCRIPT.new()
	transformer.name = "TransformerCabinet"
	_world.add_child(transformer)
	transformer.global_position = _bo_grounded(ga, TRANSFORMER_OFFSET)
	transformer.rotation.y = by
	transformer.setup()
	# Neighbour buildings — SW solar-roof + NW workshop.
	var nb_sw = _NEIGHBOR_SCRIPT.new()
	nb_sw.name = "NeighborBuilding_SW"
	_world.add_child(nb_sw)
	nb_sw.build_at(_bo_grounded(ga, NEIGHBOR_SW["offset"]), NEIGHBOR_SW["size"],
		NEIGHBOR_SW["body"], NEIGHBOR_SW["text"], NEIGHBOR_SW["sign"], by, NEIGHBOR_SW["seed"])
	var nb_nw = _NEIGHBOR_SCRIPT.new()
	nb_nw.name = "NeighborBuilding_NW"
	_world.add_child(nb_nw)
	nb_nw.build_at(_bo_grounded(ga, NEIGHBOR_NW["offset"]), NEIGHBOR_NW["size"],
		NEIGHBOR_NW["body"], NEIGHBOR_NW["text"], NEIGHBOR_NW["sign"], by, NEIGHBOR_NW["seed"])
	print("[ExteriorManager] Exterior props: sidewalk + crosswalk + %d markings + %d tree clusters + %d power poles + transformer + 2 neighbour buildings" \
		% [ROAD_MARKINGS.size(), TREE_OFFSETS.size(), POWER_POLE_OFFSETS.size()])
