extends Node3D

class_name InteriorLightingManager

# =============================================================================
# #195 follow-up — Interior lighting extracted from MainWorld.gd.
# =============================================================================
# Owns the interior TL bars and overhead spotlight grid inside the building
# shell. MainWorld instantiates one of these as a child node and calls
# setup(self) then build_all(anchor) exactly once during world setup; the
# manager defers to MainWorld for canonical helpers (_shell, _world_yaw,
# _player_spawn_pos) and parents spawned light nodes under the building
# shell so the runtime scene tree shape is identical to the pre-extract
# layout.

# Reference back to MainWorld for _shell / _world_yaw / _player_spawn_pos
# / _build_overhead_fixture etc. Set in _ready() as a fallback; setup()
# is the canonical assignment path.
var _world : Node = null

func _ready() -> void:
	if _world == null:
		_world = get_parent()

# ── Public setup / entry points ─────────────────────────────────────────────
func setup(world: Node) -> void:
	_world = world

func build_all(anchor: Vector3) -> void:
	if _world == null:
		_world = get_parent()
	_spawn_overhead_lights()

# =============================================================================
# OVERHEAD LIGHTS — #107
# =============================================================================
## Hang industrial-style bay lights from the ceiling in a 5×5 grid centred on
## the player spawn so the production floor is no longer pitch-dark. Each
## fixture has a visible white bar mesh (emissive so you can see it), a small
## dark housing above, and an OmniLight3D with warm-white tint and 25 m range.
## The flashlight is still available for inspecting machinery up close, but
## you can now actually see the room without it.
func _spawn_overhead_lights() -> void:
	# Rebuilt 2026-07-06 (operator request): per-hall placement in the
	# georeferenced BUILDING FRAME instead of a grid over the shell AABB.
	# The AABB of the 40-deg-rotated building is a much larger rectangle
	# than the building itself, so the old 7x7 grid hung bars outside the
	# walls ("TL bars floating in the yard") and its footprint cull (the
	# same AABB rectangle) could never reject them.
	#
	# Building frame (tools/generate_building.py): origin at the NE corner
	# of the gabled block, +X toward SW along the long axis (0..150.7),
	# +Z toward NW across it (0..71.6). The affine below maps it to PC
	# (derived from the survey georeference); Plant.pc_to_scene_with_y then
	# lands each bar in the scene with the canonical yaw + anchor applied.
	# Lighting spawns from _spawn_road_and_parking (early in world build) but
	# Plant.init() runs later in the same build pass — wait for it. A few
	# frames at most; bail out after 5 s so a broken init can't hang forever.
	var waited : int = 0
	while not (has_node("/root/Plant") and Plant.is_initialized()):
		waited += 1
		if waited > 300:
			push_warning("[InteriorLightingManager] Plant never initialized — overhead lights skipped")
			return
		await get_tree().process_frame
	var root := Node3D.new()
	root.name = "OverheadLights"
	(_world as Node3D).add_child(root)
	const BF_PC_O := Vector2(573.404, 463.647)   # building-frame origin in PC
	const BF_PC_X := Vector2(-0.64279, 0.76604)  # PC delta per +1 m building X
	const BF_PC_Z := Vector2(-0.76604, -0.64279) # PC delta per +1 m building Z
	var floor_y : float = Plant.pc_to_scene(Vector2(500.0, 500.0)).y
	# Bar long axis must run along the halls (building Z). Building Z is NOT
	# aligned with the PC north axis — it bears -130 deg in PC (the 40 deg
	# building azimuth) — so `world_yaw + PI/2` misses by 50 deg and lays the
	# tubes diagonally (herringbone). Derive the yaw straight from BF_PC_Z:
	# rotate that PC-frame axis into the scene the exact way pc_to_scene does
	# (Basis(UP, world_yaw)), then take the yaw that rotates local +X onto it
	# (atan2(-dir.z, dir.x) — Godot +Y rotation convention).
	var _bz_scene : Vector3 = Plant.world_basis_y() * Vector3(BF_PC_Z.x, 0.0, BF_PC_Z.y)
	var bar_yaw : float = atan2(-_bz_scene.z, _bz_scene.x)
	# Realistic first pass — one row of 6 under each arc crest, plus rows in
	# the flat west wing / SE wing / low annex. Operator tunes count later.
	# Each spot: [bf_x, bar_height, bf_z, roof_underside_height]. The 4th value
	# drives the mounting rod — the bar hangs from a visible drop rod to the
	# roof skin instead of floating in mid-air (operator report).
	var spots : Array = []
	for bay in range(4):
		var cx := 15.0 + 30.0 * float(bay)      # bay centreline (arc crest 10.4 m)
		for i in range(6):
			spots.append([cx, 9.6, 5.0 + 10.2 * float(i), 10.35])
	for x in [128.0, 143.0]:                     # west wing (flat 7 m roof)
		for z in [8.0, 16.0, 24.0]:
			spots.append([x, 6.5, z, 6.95])
	for z in [38.0, 46.0, 54.0]:                 # SE wing (7 m roof)
		spots.append([126.0, 6.5, z, 6.95])
	for i in range(6):                           # annex (4.6 m roof)
		var ax : float = 63.0 + 13.0 * float(i)
		# ANNEX_W (x 57..81) is stepped and only reaches Z=66, so a bar centred
		# ON z=66 straddles the south exterior wall. Pull the two west-annex
		# bars (x<81) north to z=63.5 so they sit fully inside; the x>=81 bars
		# stay at z=66 where the annex extends fully south.
		var az : float = 63.5 if ax < 81.0 else 66.0
		spots.append([ax, 4.1, az, 4.55])
	var rod_mat := StandardMaterial3D.new()
	rod_mat.albedo_color = Color(0.16, 0.16, 0.17)
	rod_mat.roughness = 0.7
	var n_built : int = 0
	for s in spots:
		var pcv : Vector2 = BF_PC_O + BF_PC_X * float(s[0]) + BF_PC_Z * float(s[2])
		var pos : Vector3 = Plant.pc_to_scene_with_y(pcv, floor_y + float(s[1]))
		_build_overhead_fixture(root, pos)
		var fixture := root.get_child(root.get_child_count() - 1) as Node3D
		if fixture != null:
			fixture.rotation.y = bar_yaw
			# Mounting rod: thin steel drop from the roof underside to the bar.
			var rod_len : float = maxf(float(s[3]) - float(s[1]), 0.15)
			var rod := MeshInstance3D.new()
			var rb := BoxMesh.new()
			rb.size = Vector3(0.05, rod_len, 0.05)
			rod.mesh = rb
			rod.material_override = rod_mat
			fixture.add_child(rod)
			rod.position = Vector3(0.0, 0.12 + rod_len * 0.5, 0.0)
		n_built += 1
	print("[InteriorLightingManager] Overhead TL bars: %d placed per-hall (building-frame layout, rod-mounted)" % n_built)

## Build a single TL-bar bay-light fixture (industrial fluorescent troffer).
## Operator complaint: "ceiling lights are FLOODLIGHTS, not TL bars".
## Solution: (1) longer thin emissive bar mesh shaped like a real 1.5 m
## fluorescent tube; (2) dropped the OmniLight3D — its 25 m omni_range was
## the "floodlight" behaviour AND bled light outside the shell when the
## fixture sat near a wall. A single low-energy SpotLight3D aimed -Y keeps
## the floor lit without leaking into the sky outside.
## Long axis of the bar lies along local +X so a row of fixtures forms
## parallel TL strips along the building's long wall.
func _build_overhead_fixture(parent: Node3D, pos: Vector3) -> void:
	var fixture := Node3D.new()
	fixture.position = pos
	parent.add_child(fixture)
	# 1.5 m TL tube — longer + thinner than the old 1.6×0.10×0.32 box so it
	# reads as a real fluorescent troffer rather than a panel floodlight.
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.5, 0.08, 0.10)
	bar.mesh = bb
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.96, 0.97, 0.92)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(1.0, 0.95, 0.84)
	bar_mat.emission_energy_multiplier = 3.0
	bar.material_override = bar_mat
	fixture.add_child(bar)
	# Dark steel troffer housing above the tube — long, thin, slightly wider
	# than the tube. Same long axis (local +X) as the bar.
	var hous := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(1.7, 0.10, 0.22)
	hous.mesh = hb
	hous.position = Vector3(0.0, 0.10, 0.0)
	var hous_mat := StandardMaterial3D.new()
	hous_mat.albedo_color = Color(0.22, 0.22, 0.24)
	hous_mat.metallic = 0.4
	hous_mat.roughness = 0.6
	hous.material_override = hous_mat
	fixture.add_child(hous)
	# Downward SpotLight3D INSTEAD of OmniLight3D so light stays inside the
	# building. SpotLight3D fires along its local -Z, so rotate -90° on +X
	# to aim straight down.
	var spot := SpotLight3D.new()
	spot.light_energy = 2.0
	spot.spot_range = 14.0
	spot.spot_angle = 55.0
	spot.light_color = Color(1.0, 0.96, 0.86)
	spot.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90.0)), Vector3(0.0, -0.05, 0.0))
	fixture.add_child(spot)
