extends Node3D
class_name OSMTerrainLoader

## Runtime consumer for the OSM/PDOK/AHN5/3DBAG terrain baker
## (tools/osm_terrain_baker/bake.py).
##
## At world startup MainWorld instantiates one of these and calls `load_terrain()`.
## If the three baked files exist (in res:// preferred, then user:// fallback)
## the loader:
##   1. Instantiates terrain.glb under self/Terrain (replaces the flat 200x200m
##      PlaneMesh that MainWorld._spawn_exterior_ground would otherwise build).
##   2. Instantiates buildings.glb under self/Buildings (replaces the two
##      hardcoded NeighborBuilding stand-ins).
##   3. Reads osm_furniture.json and spawns matching exterior props
##      (TreeCluster / PowerPole / procedural bollards & signs) at each entry.
##
## If ANY of the three are missing the loader logs a single warning and
## returns false from load_terrain() — caller (MainWorld) should then fall
## back to its hardcoded emitters.
##
## Axes match the project canonical convention (forward = -Z, right = +X,
## up = +Y); the baker writes its outputs in this frame directly so no
## further swizzles are needed here.

const RES_TERRAIN_PATH   := "res://assets/terrain/terrain.glb"
const RES_BUILDINGS_PATH := "res://assets/terrain/buildings.glb"
const RES_FURNITURE_PATH := "res://assets/terrain/osm_furniture.json"

const USER_TERRAIN_PATH   := "user://terrain/terrain.glb"
const USER_BUILDINGS_PATH := "user://terrain/buildings.glb"
const USER_FURNITURE_PATH := "user://terrain/osm_furniture.json"

@export var anchor_offset : Vector3 = Vector3.ZERO
@export var build_collision_for_terrain : bool = true
@export var spawn_furniture : bool = true

# Counts populated by load_terrain() — useful for the MainWorld log line.
var loaded_terrain   : bool = false
var loaded_buildings : bool = false
var spawned_furniture_count : int = 0
var spawned_road_count : int = 0


func load_terrain() -> bool:
	## Returns true if at least the terrain.glb was loaded (the minimum useful
	## payload). MainWorld can still spawn its hardcoded ground if this is false.
	var any := false
	any = _try_load_terrain() or any
	any = _try_load_buildings() or any
	if spawn_furniture:
		any = _try_load_furniture() or any
	if not any:
		push_warning("[OSMTerrainLoader] no baked assets found in res:// or user://terrain/ — falling back to MainWorld hardcoded emitters.")
	return any


# ─────────────────────────────────────────────────────────────────────────────
# Terrain mesh
# ─────────────────────────────────────────────────────────────────────────────
func _try_load_terrain() -> bool:
	var path := _resolve_path(RES_TERRAIN_PATH, USER_TERRAIN_PATH)
	if path == "":
		return false
	var inst := _instantiate_glb(path)
	if inst == null:
		return false
	inst.name = "Terrain"
	inst.position = anchor_offset
	add_child(inst)
	if build_collision_for_terrain:
		_add_static_collision_recursive(inst)
	loaded_terrain = true
	print("[OSMTerrainLoader] loaded terrain from %s" % path)
	return true


# ─────────────────────────────────────────────────────────────────────────────
# Building extrusions
# ─────────────────────────────────────────────────────────────────────────────
func _try_load_buildings() -> bool:
	var path := _resolve_path(RES_BUILDINGS_PATH, USER_BUILDINGS_PATH)
	if path == "":
		return false
	var inst := _instantiate_glb(path)
	if inst == null:
		return false
	inst.name = "Buildings"
	inst.position = anchor_offset
	add_child(inst)
	# Buildings get StaticBody collision too so the player can't walk through
	# the neighbours.
	_add_static_collision_recursive(inst)
	loaded_buildings = true
	print("[OSMTerrainLoader] loaded buildings from %s" % path)
	return true


# ─────────────────────────────────────────────────────────────────────────────
# OSM furniture (trees, signs, bollards, benches, lamps, power poles) + roads
# ─────────────────────────────────────────────────────────────────────────────
func _try_load_furniture() -> bool:
	var path := _resolve_path(RES_FURNITURE_PATH, USER_FURNITURE_PATH)
	if path == "":
		return false
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var txt := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[OSMTerrainLoader] osm_furniture.json malformed at %s" % path)
		return false
	var root := parsed as Dictionary

	var holder := Node3D.new()
	holder.name = "Furniture"
	holder.position = anchor_offset
	add_child(holder)

	var items : Array = root.get("furniture", [])
	for it in items:
		var d := it as Dictionary
		if d == null:
			continue
		var kind : String = d.get("kind", "")
		var x : float = d.get("x", 0.0)
		var z : float = d.get("z", 0.0)
		var tags : Dictionary = d.get("tags", {})
		_spawn_furniture_item(holder, kind, Vector3(x, 0.0, z), tags)
	spawned_furniture_count = items.size()

	# OSM roads are baked into terrain.glb (asphalt ribbons), but the polyline
	# data is preserved in osm_furniture.json so MainWorld can also use it to
	# place lane markings / crosswalks / etc. at runtime. We just count them
	# here for the log.
	var roads : Array = root.get("roads", [])
	spawned_road_count = roads.size()

	print("[OSMTerrainLoader] loaded %d furniture items + %d road polylines from %s"
		% [spawned_furniture_count, spawned_road_count, path])
	return true


func _spawn_furniture_item(holder: Node3D, kind: String, pos: Vector3, tags: Dictionary) -> void:
	## Dispatch to the matching exterior/ scene. Unknown kinds become a small
	## marker cube so they're visible during a bake review pass.
	match kind:
		"tree":
			_spawn_tree(holder, pos)
		"power_pole":
			_spawn_power_pole(holder, pos)
		"lamp":
			_spawn_lamp(holder, pos)
		"bollard":
			_spawn_bollard(holder, pos)
		"traffic_light", "stop_sign", "traffic_sign":
			_spawn_sign(holder, pos, kind, tags)
		"bench":
			_spawn_bench(holder, pos)
		"bin":
			_spawn_bin(holder, pos)
		_:
			_spawn_marker(holder, pos, kind)


# ─────────────────────────────────────────────────────────────────────────────
# Per-kind spawners — keep them all in this file so the loader is self-contained.
# Each delegates to the existing exterior/ classes where one exists; otherwise
# emits a primitive-mesh stand-in good enough for a first-pass.
# ─────────────────────────────────────────────────────────────────────────────
func _spawn_tree(holder: Node3D, pos: Vector3) -> void:
	var tc_script := load("res://src/scenes/world/exterior/TreeCluster.gd")
	if tc_script != null:
		var tc : TreeCluster = TreeCluster.new()
		holder.add_child(tc)
		tc.position = pos
		# Single-tree cluster at the OSM node — radius 0.5m, n=1.
		tc.cluster_at(Vector3.ZERO, 0.5, 1, int(pos.x * 1000.0 + pos.z))
		return
	# Fallback: cylinder + sphere.
	_spawn_marker(holder, pos, "tree")


func _spawn_power_pole(holder: Node3D, pos: Vector3) -> void:
	var pp_script := load("res://src/scenes/world/exterior/PowerPole.gd")
	if pp_script != null:
		var p : PowerPole = PowerPole.new()
		holder.add_child(p)
		p.position = pos
		if p.has_method("build_pole"):
			p.call("build_pole")
		return
	_spawn_marker(holder, pos, "power_pole")


func _spawn_lamp(holder: Node3D, pos: Vector3) -> void:
	# No dedicated street-lamp class — use Floodlight which is the closest
	# match (a pole + a fixture). Caller height/angle defaults are fine.
	var fl_script := load("res://src/scenes/world/exterior/Floodlight.gd")
	if fl_script != null:
		var fl := Node3D.new()
		fl.set_script(fl_script)
		holder.add_child(fl)
		fl.position = pos
		if fl.has_method("build"):
			fl.call("build")
		return
	_spawn_marker(holder, pos, "lamp")


func _spawn_bollard(holder: Node3D, pos: Vector3) -> void:
	## Cast-iron bollard — 1.0m tall, 0.12m diameter, dark grey. Static collision.
	var n := StaticBody3D.new()
	n.name = "Bollard"
	holder.add_child(n)
	n.position = pos
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.06
	m.bottom_radius = 0.07
	m.height = 1.0
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.18, 0.20)
	mat.roughness = 0.6
	mi.material_override = mat
	mi.position.y = 0.5
	n.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.height = 1.0
	sh.radius = 0.07
	cs.shape = sh
	cs.position.y = 0.5
	n.add_child(cs)


func _spawn_sign(holder: Node3D, pos: Vector3, kind: String, _tags: Dictionary) -> void:
	## Generic post-mounted sign — 2.2m post + 0.3x0.3 plate. Plate colour by kind.
	var n := Node3D.new()
	n.name = "Sign_" + kind
	holder.add_child(n)
	n.position = pos
	# Post
	var post := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.035
	pm.bottom_radius = 0.035
	pm.height = 2.2
	post.mesh = pm
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.55, 0.55, 0.55)
	post_mat.roughness = 0.5
	post.material_override = post_mat
	post.position.y = 1.1
	n.add_child(post)
	# Plate
	var plate := MeshInstance3D.new()
	var pl := BoxMesh.new()
	pl.size = Vector3(0.4, 0.4, 0.02)
	plate.mesh = pl
	var plate_mat := StandardMaterial3D.new()
	match kind:
		"stop_sign":
			plate_mat.albedo_color = Color(0.85, 0.10, 0.10)
		"traffic_light":
			plate_mat.albedo_color = Color(0.15, 0.15, 0.15)
		_:
			plate_mat.albedo_color = Color(0.95, 0.85, 0.10)
	plate.material_override = plate_mat
	plate.position.y = 2.1
	n.add_child(plate)


func _spawn_bench(holder: Node3D, pos: Vector3) -> void:
	var n := StaticBody3D.new()
	n.name = "Bench"
	holder.add_child(n)
	n.position = pos
	var seat := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(1.6, 0.06, 0.4)
	seat.mesh = sm
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.30, 0.18)
	wood.roughness = 0.85
	seat.material_override = wood
	seat.position.y = 0.45
	n.add_child(seat)
	var back := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.4, 0.06)
	back.mesh = bm
	back.material_override = wood
	back.position = Vector3(0, 0.7, -0.17)
	n.add_child(back)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(1.6, 0.5, 0.4)
	cs.shape = sh
	cs.position.y = 0.5
	n.add_child(cs)


func _spawn_bin(holder: Node3D, pos: Vector3) -> void:
	var n := StaticBody3D.new()
	n.name = "Bin"
	holder.add_child(n)
	n.position = pos
	var mi := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = 0.22
	m.bottom_radius = 0.22
	m.height = 0.9
	mi.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.45, 0.25)
	mi.material_override = mat
	mi.position.y = 0.45
	n.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := CylinderShape3D.new()
	sh.height = 0.9
	sh.radius = 0.22
	cs.shape = sh
	cs.position.y = 0.45
	n.add_child(cs)


func _spawn_marker(holder: Node3D, pos: Vector3, label: String) -> void:
	## Last-resort visible cube — 25cm magenta, no collision. Useful so the
	## operator sees baker output even for kinds without a dedicated emitter.
	var mi := MeshInstance3D.new()
	mi.name = "Marker_" + label
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 0.25)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.1, 0.9)
	mi.material_override = mat
	holder.add_child(mi)
	mi.position = pos + Vector3(0, 0.5, 0)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _resolve_path(res_path: String, user_path: String) -> String:
	## Prefer the bundled res:// asset, fall back to user:// (so a re-bake during
	## a play session lands without re-packaging).
	if FileAccess.file_exists(res_path):
		return res_path
	if FileAccess.file_exists(user_path):
		return user_path
	return ""


func _instantiate_glb(path: String) -> Node3D:
	var res := load(path)
	if res == null:
		push_warning("[OSMTerrainLoader] failed to load %s" % path)
		return null
	if res is PackedScene:
		var n := (res as PackedScene).instantiate()
		if n is Node3D:
			return n as Node3D
		push_warning("[OSMTerrainLoader] %s instantiated non-Node3D root" % path)
		return null
	if res is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = res
		return mi
	push_warning("[OSMTerrainLoader] %s loaded as unexpected type %s" % [path, res.get_class()])
	return null


func _add_static_collision_recursive(n: Node) -> void:
	## Walk the GLB scene and slap a StaticBody3D + ConcavePolygonShape3D under
	## every MeshInstance3D so the player can walk on the terrain and bump into
	## the building extrusions.
	for child in n.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			# Skip if a StaticBody3D is already attached.
			var already := false
			for sib in mi.get_children():
				if sib is StaticBody3D:
					already = true
					break
			if already:
				continue
			var body := StaticBody3D.new()
			mi.add_child(body)
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			body.add_child(cs)
		_add_static_collision_recursive(child)
