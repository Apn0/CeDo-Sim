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

## Measured building frame, cached from the one fit per boot (the shell is
## static, so the mapping never changes while the world lives).
## {"o": Vector2 scene-XZ of bf(0,0), "x"/"z": unit Vector2 axes, "err": mean
## roof error m} — or {} until the fit lands / when it failed. Consumers
## (MapOverlay building outline) MUST treat {} as "no frame: draw nothing",
## never substitute a baked affine — that is the exact two-copies-of-one-
## stale-mapping failure documented below.
var _building_frame : Dictionary = {}

func get_building_frame() -> Dictionary:
	return _building_frame

func _ready() -> void:
	if _world == null:
		_world = get_parent()

# ── Public setup / entry points ─────────────────────────────────────────────
func setup(world: Node) -> void:
	_world = world

func build_all(_anchor: Vector3) -> void:
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
	# +Z toward NW across it (0..71.6). It reaches the scene ONLY through
	# _fit_building_frame below (measured off the shell's collision faces) —
	# the hand-baked BF->PC affine that used to live here is gone (2701275).
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
	var floor_y : float = Plant.pc_to_scene(Vector2(500.0, 500.0)).y
	# ── FIT THE BUILDING FRAME FROM THE MEASURED SHELL ────────────────────────
	# The old path mapped building-frame spots through HAND-BAKED affine
	# constants (BF_PC_O/X/Z, copied 2026-07-06). Measured 2026-07-20: the bay
	# bars those constants produce have ZERO shell faces above their columns —
	# the whole bay grid stood outside the real arcs, rods "mounted to air"
	# (38/39, worst 5.67 m). The regression check agreed with the bars because
	# it used a COPY of the same constants: two copies of one stale mapping
	# validating each other. Now the frame is fitted to the shell's actual
	# collision geometry every boot, and scored against known roof heights;
	# if the fit fails it says so and falls back loudly.
	await get_tree().physics_frame
	var fit : Dictionary = _fit_building_frame(floor_y)
	_building_frame = fit   # cache for external consumers (MapOverlay outline)
	if fit.is_empty():
		push_warning("[InteriorLightingManager] building-frame fit FAILED — overhead lights skipped (better absent than floating)")
		return
	var f_o : Vector2 = fit["o"]
	var f_x : Vector2 = fit["x"]
	var f_z : Vector2 = fit["z"]
	# Bar long axis runs along the halls (building Z) — straight from the
	# FITTED Z axis now, no PC detour (atan2(-dz, dx) = Godot +Y yaw that
	# rotates local +X onto that direction).
	var bar_yaw : float = atan2(-f_z.y, f_z.x)
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
		var xz : Vector2 = f_o + f_x * float(s[0]) + f_z * float(s[2])
		var pos : Vector3 = Vector3(xz.x, floor_y + float(s[1]), xz.y)
		_build_overhead_fixture(root, pos)
		var fixture := root.get_child(root.get_child_count() - 1) as Node3D
		if fixture != null:
			fixture.rotation.y = bar_yaw
			# Mounting rod: thin steel drop from the roof underside to the bar.
			var rod_len : float = maxf(float(s[3]) - float(s[1]), 0.15)
			var rod := MeshInstance3D.new()
			rod.name = "MountRod"
			var rb := BoxMesh.new()
			rb.size = Vector3(0.05, rod_len, 0.05)
			rod.mesh = rb
			rod.material_override = rod_mat
			fixture.add_child(rod)
			rod.position = Vector3(0.0, 0.12 + rod_len * 0.5, 0.0)
		n_built += 1
	# MEASURE THE ROOF, don't assume it. The rod length used to come from s[3],
	# a per-zone hand-typed "roof underside" constant. Measured 2026-07-20 by the
	# regression raycast: 38 of 39 rods ended in MID-AIR, worst 5.67 m short —
	# the bays are arched, so no constant can follow the roof. The operator's
	# question ("how does a mount mounted to air not fall?") has an honest
	# answer: these are static meshes, gravity only acts on RigidBody3D, so a
	# wrongly-drawn rod just hangs where the code drew it forever.
	# One physics frame so the shell's static colliders are queryable, then
	# stretch every rod to the measured roof hit directly above its bar.
	await get_tree().physics_frame
	var space := root.get_world_3d().direct_space_state
	var rod_hits := 0
	var rod_misses := 0
	for fixture in root.get_children():
		if not (fixture is Node3D):
			continue
		var rod := (fixture as Node).get_node_or_null("MountRod") as MeshInstance3D
		if rod == null or space == null:
			continue
		var pos : Vector3 = (fixture as Node3D).global_position
		var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.UP * 45.0)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			# Nothing above this bar to mount to — keep the fallback rod but say
			# so loudly; a silent skip is how the air-mounts shipped.
			rod_misses += 1
			push_warning("[InteriorLightingManager] no roof above TL bar at %s — rod left at fallback length" % str(pos))
			continue
		var roof_y : float = (hit["position"] as Vector3).y
		var rod_len : float = maxf(roof_y - pos.y - 0.12, 0.15)
		(rod.mesh as BoxMesh).size = Vector3(0.05, rod_len, 0.05)
		rod.position = Vector3(0.0, 0.12 + rod_len * 0.5, 0.0)
		rod_hits += 1
	print("[InteriorLightingManager] Overhead TL bars: %d placed; rods measured to roof: %d stretched, %d no-roof fallback"
		% [n_built, rod_hits, rod_misses])

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

	# Aging starter flicker chance (1 in 10 fixtures has an authentic micro-flicker)
	if randf() < 0.12:
		fixture.set_meta("is_flicker_fixture", true)
		_flicker_fixtures.append({"fixture": fixture, "spot": spot, "bar_mat": bar_mat, "phase": randf() * TAU})

var _flicker_fixtures : Array = []

func _process(delta: float) -> void:
	if _flicker_fixtures.is_empty():
		return
	var t := Time.get_ticks_msec() * 0.001
	for f in _flicker_fixtures:
		var spot : SpotLight3D = f.get("spot")
		var bar_mat : StandardMaterial3D = f.get("bar_mat")
		var ph : float = float(f.get("phase", 0.0))
		# High-frequency starter jitter modulated by low-frequency envelope
		var flk : float = sin(t * 37.0 + ph) * sin(t * 7.3 + ph)
		if flk > 0.88:
			var dip : float = randf_range(0.3, 0.9)
			if spot and is_instance_valid(spot):
				spot.light_energy = dip * 2.0
			if bar_mat:
				bar_mat.emission_energy_multiplier = dip * 3.0
		else:
			if spot and is_instance_valid(spot):
				spot.light_energy = 2.0
			if bar_mat:
				bar_mat.emission_energy_multiplier = 3.0


# =============================================================================
# BUILDING-FRAME FIT — measure, don't assume (2026-07-20)
# =============================================================================
## Fit the building frame (bf: origin corner, +X long axis 0..150.7, +Z cross
## axis 0..71.5) onto the shell's ACTUAL collision geometry:
##   1. collect the shell's static-collision vertices, project to scene XZ;
##   2. the hull's oriented box gives the frame axes + centre (yaw ambiguity: 2);
##   3. break the ambiguity by MEASURING roof heights with downward rays at
##      probe points whose expected heights differ per orientation (annex 4.6 m
##      vs east wing 7.0 m vs bay arcs ~10.4 m) and keeping the better score.
## Returns {"o": Vector2 scene-XZ of bf(0,0), "x": unit Vector2, "z": unit
## Vector2, "err": mean |measured-expected| m} or {} on failure.
func _fit_building_frame(floor_y: float) -> Dictionary:
	var shell := _world.find_child("ShellMesh", true, false) as MeshInstance3D
	if shell == null:
		return {}
	var faces := PackedVector3Array()
	var xf := Transform3D.IDENTITY
	for ch in shell.get_children():
		if ch is StaticBody3D:
			var cs := (ch as Node).get_child(0) as CollisionShape3D
			if cs != null and cs.shape is ConcavePolygonShape3D:
				faces = (cs.shape as ConcavePolygonShape3D).get_faces()
				xf = cs.global_transform
				break
	if faces.is_empty():
		return {}
	var pts := PackedVector2Array()
	for i in range(0, faces.size(), 3):
		var w := xf * faces[i]
		pts.append(Vector2(w.x, w.z))
	var hull := Geometry2D.convex_hull(pts)
	if hull.size() < 3:
		return {}
	# Oriented box via rotating calipers over hull edge directions.
	var best_area := INF
	var best_dir := Vector2.RIGHT
	var best_box := Rect2()
	for i in hull.size() - 1:
		var e := (hull[i + 1] - hull[i])
		if e.length() < 0.5:
			continue
		var d := e.normalized()
		var n := Vector2(-d.y, d.x)
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in hull:
			var u := Vector2(q.dot(d), q.dot(n))
			lo.x = minf(lo.x, u.x); lo.y = minf(lo.y, u.y)
			hi.x = maxf(hi.x, u.x); hi.y = maxf(hi.y, u.y)
		var area := (hi.x - lo.x) * (hi.y - lo.y)
		if area < best_area:
			best_area = area
			best_dir = d
			best_box = Rect2(lo, hi - lo)
	# Long axis of the box = bf +X (150.7 m); short = bf +Z (71.5 m).
	var span := best_box.size
	var d_long := best_dir
	var d_short := Vector2(-best_dir.y, best_dir.x)
	if span.x < span.y:
		var tmp := d_long; d_long = d_short; d_short = tmp
		span = Vector2(span.y, span.x)
	# Sanity: the measured box must resemble the 150.7 x 71.5 outline.
	if absf(span.x - 150.7) > 12.0 or absf(span.y - 71.5) > 12.0:
		push_warning("[InteriorLightingManager] shell OBB %.1f x %.1f does not match the 150.7 x 71.5 outline" % [span.x, span.y])
		return {}
	# Two yaw candidates (long axis either way); each fixes origin at a
	# different corner. Score both by measured roof heights.
	var space := shell.get_world_3d().direct_space_state
	var probes := [
		[Vector2(15.0, 30.0), 10.4], [Vector2(45.0, 30.0), 10.4],
		[Vector2(75.0, 30.0), 10.4], [Vector2(105.0, 30.0), 10.4],
		[Vector2(135.0, 15.0), 7.0], [Vector2(126.0, 46.0), 7.0],
		[Vector2(69.0, 63.5), 4.6],  [Vector2(100.0, 68.0), 4.6],
	]
	var best : Dictionary = {}
	var best_err := INF
	for flip in [1.0, -1.0]:
		var ax : Vector2 = d_long * flip
		# Right-handed bf: +Z must be the short axis such that the box interior
		# lies on its positive side from the chosen origin corner.
		for zsign in [1.0, -1.0]:
			var az : Vector2 = d_short * zsign
			# Origin corner: hull point minimising projection on both axes.
			var o := Vector2.ZERO
			var mind := INF
			for q in hull:
				var proj := q.dot(ax) + q.dot(az)
				if proj < mind:
					mind = proj
					o = q
			var err := 0.0
			var n_hit := 0
			for pr in probes:
				var bf : Vector2 = pr[0]
				var want : float = pr[1]
				var at : Vector2 = o + ax * bf.x + az * bf.y
				var q2 := PhysicsRayQueryParameters3D.create(
					Vector3(at.x, floor_y + 60.0, at.y),
					Vector3(at.x, floor_y - 1.0, at.y))
				var hit := space.intersect_ray(q2)
				if hit.is_empty():
					err += 30.0        # no roof where one is expected: heavy penalty
					continue
				n_hit += 1
				err += absf((float((hit["position"] as Vector3).y) - floor_y) - want)
			err /= float(probes.size())
			if err < best_err:
				best_err = err
				best = {"o": o, "x": ax, "z": az, "err": err}
	if best.is_empty() or best_err > 2.5:
		push_warning("[InteriorLightingManager] frame fit rejected (mean roof error %.2f m)" % best_err)
		return {}
	print("[InteriorLightingManager] building frame FITTED from shell: o=%s x=%s z=%s (mean roof err %.2f m)"
		% [str(best["o"]), str(best["x"]), str(best["z"]), best_err])
	return best
