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
	_spawn_floodlights(anchor)

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
	# Bay lights now live in the BUILDING's LOCAL frame: parented under the
	# ShellMesh so they inherit its transform, gridded along the shell's local
	# X/Z (long axis = local X), and clipped against the shell's LOCAL AABB
	# rectangle. This fixes the "ceiling lights floating in the sky outside
	# the building" complaint that surfaced when the shell carried any yaw —
	# previously the grid stepped along world X/Z and the AABB-rectangle in/
	# out test ran in world space too, so the kept cells covered a rotated
	# bounding rectangle bigger than the building.
	# Long axis of each TL bar is local +X (matches operator spec).
	var shell : MeshInstance3D = _world.call("_shell")
	var parent_node : Node3D = shell if shell != null else (_world as Node3D)
	var root := Node3D.new()
	root.name = "OverheadLights"
	parent_node.add_child(root)
	# WORLD-cluster fix: parent the bay-light grid under a rotation node that
	# carries `(world_yaw - shell_local_yaw)` so the row direction tracks the
	# canonical bale-yard yaw even when shell.global_transform already bakes
	# in a different yaw. Without this the grid was rotated by whatever the
	# shell's mesh-local axes carry, which disagreed with the operator-drawn
	# yards. When parent_node IS the shell, `shell_local_yaw` is the yaw
	# encoded in shell.global_transform; subtracting it lands the grid back
	# in the canonical frame.
	var shell_local_yaw : float = 0.0
	if shell != null:
		shell_local_yaw = shell.global_transform.basis.get_euler().y
	var orient_compensation : float = float(_world.call("_world_yaw")) - shell_local_yaw
	root.rotation.y = orient_compensation
	# Compute the LOCAL-frame footprint (rectangle in shell's local XZ).
	var local_aabb : AABB
	if shell != null and shell.mesh != null:
		local_aabb = shell.mesh.get_aabb()
	else:
		# Fallback: 60×60 m box around player spawn so a dev still sees lights.
		var p : Vector3 = _world.get("_player_spawn_pos")
		local_aabb = AABB(Vector3(p.x - 30, 0, p.z - 30), Vector3(60, 8, 60))
	# Hang the bars under the EAVE line, not the AABB top: the AABB peaks at
	# the rooftop penthouse (12.4 m) while the arched bays crest at 10.4 m —
	# anchoring to the AABB floated the whole grid inside the vaults (the
	# "grid blocking the top of each roof arc" the operator reported).
	# 6.9 m = 0.5 m under the measured 7.4 m eave, clear of every roof plane.
	var ceil_y_local : float = local_aabb.position.y + minf(local_aabb.size.y - 0.4, 6.9)
	var x0 := local_aabb.position.x; var x1 := x0 + local_aabb.size.x
	var z0 := local_aabb.position.z; var z1 := z0 + local_aabb.size.z
	var local_footprint := PackedVector2Array([
		Vector2(x0, z0), Vector2(x1, z0),
		Vector2(x1, z1), Vector2(x0, z1)])
	var spacing : float = 18.0
	var n : int = 7
	var n_kept : int = 0
	var n_culled : int = 0
	var cx := (x0 + x1) * 0.5
	var cz := (z0 + z1) * 0.5
	for ix in range(n):
		for iz in range(n):
			var fx : float = (float(ix) - float(n - 1) * 0.5) * spacing
			var fz : float = (float(iz) - float(n - 1) * 0.5) * spacing
			var px : float = cx + fx
			var pz : float = cz + fz
			if not Geometry2D.is_point_in_polygon(Vector2(px, pz), local_footprint):
				n_culled += 1
				continue
			# LOCAL position under the shell. Bar's long axis is local +X.
			_build_overhead_fixture(root, Vector3(px, ceil_y_local, pz))
			n_kept += 1
	print("[InteriorLightingManager] Overhead TL bars: %d kept (shell-local %dx%d grid, %d culled outside footprint)" \
		% [n_kept, n, n, n_culled])

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

## TL-bar emissive boxes parented INSIDE the building shell — replaces the
## old wall-mounted exterior Floodlight cones. Operator notes the building
## is lit by overhead fluorescent tubes, not by floodlights aimed at the
## walls; the floodlights also rotated by `_building_yaw()` which disagreed
## with the canonical bale-yard yaw (WORLD-cluster fix).
##
## Each TL-bar is an emissive 1.5×0.08×0.10 m box (no light source — the
## SpotLight3Ds from `_spawn_overhead_lights` already supply the actual
## illumination). The bars hang from the ceiling along the building's local
## south + west wall lines so the inside of the shell reads as an industrial
## fluorescent hall at dusk/night. They're parented under the ShellMesh,
## inheriting its transform, and oriented along local +X — but the GRID step
## is rotated by `(world_yaw - shell_local_yaw)` so the row direction tracks
## the canonical yaw the bale yards drive.
func _spawn_floodlights(anchor: Vector3) -> void:
	var shell : MeshInstance3D = _world.call("_shell")
	if shell == null:
		print("[InteriorLightingManager] Floodlights skipped: no ShellMesh found")
		return
	var root := Node3D.new()
	root.name = "InteriorTLBars"
	shell.add_child(root)
	# Compute shell-local ceiling height and footprint (same pattern as
	# `_spawn_overhead_lights`).
	var local_aabb : AABB = shell.mesh.get_aabb() if shell.mesh != null else AABB(Vector3.ZERO, Vector3(40, 8, 40))
	var ceil_y_local : float = local_aabb.position.y + local_aabb.size.y - 0.45
	var x0 := local_aabb.position.x; var x1 := x0 + local_aabb.size.x
	var z0 := local_aabb.position.z; var z1 := z0 + local_aabb.size.z
	# Wall-line TL bars: two rows along the local south wall (interior face)
	# and one row along the local west wall, so the perimeter of the hall
	# reads brightly at night. Positions are in shell-LOCAL frame.
	var inset : float = 1.2
	var bar_offsets : Array = [
		Vector3(x0 + inset, ceil_y_local, z0 + inset),
		Vector3((x0 + x1) * 0.5, ceil_y_local, z0 + inset),
		Vector3(x1 - inset, ceil_y_local, z0 + inset),
		Vector3(x0 + inset, ceil_y_local, (z0 + z1) * 0.5),
	]
	for i in bar_offsets.size():
		_build_overhead_fixture(root, bar_offsets[i])
		root.get_child(i).name = "InteriorTLBar_%d" % i
	print("[InteriorLightingManager] Interior TL bars: %d emissive boxes parented under ShellMesh (replaces wall floodlights)" \
		% bar_offsets.size())
