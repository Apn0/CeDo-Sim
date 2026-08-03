extends Object

class_name TextureKit

# =============================================================================
# #195 — Texture / material factory extracted from MainWorld.gd.
# =============================================================================
# Pure static helpers: no state, no scene children. MainWorld calls
# `TextureKit.apply_textures(self, _shell())` once during _spawn_world_items.
# Internal callers pass `world` (the MainWorld node) so we can reach scene-tree
# helpers like find_child without binding to a specific class.

# =============================================================================
# PROCEDURAL TEXTURES  (no image assets exist — surface detail is generated)
# =============================================================================
static func apply_textures(world: Node, shell: MeshInstance3D) -> void:
	# Floor — worn concrete. Photo-calibrated from assets/reference_photos/
	# building/hal_0_*.png + yellow_ladders_railings_lines.png. The real CeDo
	# floor is a warm-grey-brown worn polished concrete, NOT a neutral mid-grey;
	# the previous (0.42, 0.41, 0.39) was too lifted and too neutral.
	var floor_node := world.find_child("TempFloor", true, false)
	if floor_node:
		var fm := floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
		if fm:
			# Operator pick (2026-07): Polyhaven dirty_concrete for the hall
			# floor — matches the real CeDo floor better than the photo crops.
			# Fallback chain: photo-extracted texture → procedural noise.
			var floor_mat : StandardMaterial3D = null
			var ph := world.get_node_or_null("/root/PolyhavenMaterials")
			if ph != null:
				floor_mat = ph.call("factory_floor_dirty")
			if floor_mat == null:
				floor_mat = MaterialPalette.mat_concrete_worn()
				if floor_mat.albedo_texture == null:
					floor_mat = industrial_mat(Color(0.34, 0.32, 0.30), 0.55, 0.92, false)
			fm.material_override = floor_mat
	# Building shell — painted concrete/steel. Use a SIMPLE flat material rather
	# than the triplanar-noise one: the noise normal-map combined with the .obj's
	# mixed winding was making some wall/roof faces render black on one side.
	# WallOpenings now regenerates normals from winding AND flips inward-facing
	# tris (see WallOpenings._fix_winding_outward), so the shell can use a clean
	# matte pass without the noise normal-map trickery.
	# Calibrated cream-grey from _e_kast.png (background wall) — the real walls
	# are not pure-white painted, they're a dusty cream from years of service.
	if shell:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.70, 0.68, 0.63)
		sm.roughness    = 0.94          # matte — kills bright specular hot-spots
		sm.metallic     = 0.0
		# CULL_DISABLED so back faces still render (single-sided walls would
		# disappear from one side otherwise). Godot auto-flips the normal on
		# the back face, so both sides light correctly.
		sm.cull_mode    = BaseMaterial3D.CULL_DISABLED
		# #111 — the solidified .obj now emits `usemtl shell` and `usemtl posts`
		# as separate surfaces (surface 0 = walls/roof, surface 1 = wooden
		# V-beams). If the imported mesh has multiple surfaces, override per
		# surface so the V-beams pick up the photo-calibrated timber material
		# instead of inheriting the cream shell paint. Falls back to
		# material_override on a single-surface mesh (old .obj).
		var surface_count : int = 0
		if shell.mesh != null:
			surface_count = shell.mesh.get_surface_count()
		if surface_count >= 2:
			shell.material_override = null
			shell.set_surface_override_material(0, sm)
			var timber := MaterialPalette.mat_timber_dark()
			# Apply CULL_DISABLED to timber too — posts are baked as proper
			# 6-sided boxes by solidify_building.py, but the photo material is
			# triplanar with a normal map, and CULL_DISABLED matches the shell
			# behaviour so lighting reads identically across both surfaces.
			timber.cull_mode = BaseMaterial3D.CULL_DISABLED
			shell.set_surface_override_material(1, timber)
		else:
			shell.material_override = sm
	print("[TextureKit] Procedural textures applied (floor + building)")

## Procedural surface material: world-triplanar bump + roughness noise so the
## surface has real texture under light, without needing any image files.
static func industrial_mat(base: Color, tex_scale: float, rough: float, cull_off: bool) -> StandardMaterial3D:
	var rn := FastNoiseLite.new()
	rn.frequency = 0.5
	var rough_tex := NoiseTexture2D.new()
	rough_tex.width = 256
	rough_tex.height = 256
	rough_tex.seamless = true
	rough_tex.noise = rn

	var nn := FastNoiseLite.new()
	nn.frequency = 0.9
	var normal_tex := NoiseTexture2D.new()
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 1.5
	normal_tex.noise = nn

	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = rough
	m.roughness_texture = rough_tex
	m.normal_enabled = true
	m.normal_texture = normal_tex
	m.normal_scale = 0.7
	m.uv1_triplanar = true            # works without mesh UVs (the carved shell has none)
	m.uv1_world_triplanar = true      # consistent real-world tiling
	m.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
