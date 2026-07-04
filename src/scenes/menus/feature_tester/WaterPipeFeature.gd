extends Node3D
class_name WaterPipeFeature

var _pipe_diameter : float = 0.10
var _pipe_angle    : float = 45.0
var _water_velocity: float = 6.0

# Derived — never set directly: Q = pi * r^2 * v  (m3/s)
func _flow_m3s() -> float:
	var r := _pipe_diameter * 0.5
	return PI * r * r * _water_velocity

const MOUTH_HEIGHT : float = 1.9
const PIPE_LEN     : float = 1.2
const GRAVITY      : float = 9.81
const FLOOR_Y      : float = -0.05
const ARC_STEPS    : int   = 48
const TUBE_SIDES   : int   = 12

var _assembly  : Node3D = null
var _pipe_mesh : MeshInstance3D = null
var _stream_mi : MeshInstance3D = null
var _splash_mi : MeshInstance3D = null
var _pool_mi   : MeshInstance3D = null
var _stream_mat : Material = null
var _splash_mat : Material = null
var _pool_mat   : Material = null

var _pool_volume_m3  : float = 0.0   # accumulated water in m3
var _pool_hit        : Vector3 = Vector3.ZERO
const POOL_DEPTH_M   : float = 0.15  # 15 cm effective depth — keeps radius scene-scale
const POOL_MAX_R     : float = 3.0   # hard cap: pool won't exceed 3 m radius

func feature_title() -> String:
	return "Water pipe"

func param_specs() -> Array:
	# Realistic ranges: bore 3-30 cm, angle 10-70 deg, velocity 2-12 m/s
	# At defaults (10 cm bore, 45 deg, 6 m/s):  Q = pi*(0.05)^2*6 = 47 L/s = 2820 L/min
	return [
		{"key": "pipe_diameter",  "label": "Pipe bore (m)",         "min": 0.03, "max": 0.30, "step": 0.01, "default": 0.10},
		{"key": "pipe_angle",     "label": "Pipe angle (deg down)",  "min": 10.0, "max": 70.0, "step": 1.0,  "default": 45.0},
		{"key": "water_velocity", "label": "Exit velocity (m/s)",    "min": 1.0,  "max": 12.0, "step": 0.5,  "default": 6.0},
	]

func build_content() -> void:
	# Floor
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	floor_mi.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.19)
	floor_mat.roughness = 0.95
	floor_mi.material_override = floor_mat
	floor_mi.position.y = FLOOR_Y
	add_child(floor_mi)

	# Pipe assembly
	_assembly = Node3D.new()
	_assembly.name = "PipeAssembly"
	_assembly.position = Vector3(0.0, MOUTH_HEIGHT, -0.6)
	add_child(_assembly)

	_pipe_mesh = MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = _pipe_diameter * 0.5
	cyl.bottom_radius = _pipe_diameter * 0.5
	cyl.height = PIPE_LEN
	_pipe_mesh.mesh = cyl
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.34, 0.36, 0.40)
	steel.metallic  = 0.6
	steel.roughness = 0.45
	_pipe_mesh.material_override = steel
	_pipe_mesh.rotation.x = deg_to_rad(90.0)
	_pipe_mesh.position   = Vector3(0.0, 0.0, -PIPE_LEN * 0.5)
	_assembly.add_child(_pipe_mesh)

	# Stream + splash + pool placeholders
	_stream_mi = MeshInstance3D.new()
	add_child(_stream_mi)
	_splash_mi = MeshInstance3D.new()
	add_child(_splash_mi)
	_pool_mi = MeshInstance3D.new()
	_pool_mi.position.y = FLOOR_Y + 0.001
	add_child(_pool_mi)

	# Animated water shader — built via concatenation (avoids triple-quote parse issues)
	var stream_shader := Shader.new()
	stream_shader.code = (
		"shader_type spatial;\n"
		+ "render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;\n"
		+ "uniform vec4 water_color : source_color = vec4(0.50, 0.78, 0.95, 0.84);\n"
		+ "uniform float flow_speed : hint_range(0.5, 10.0) = 5.0;\n"
		+ "uniform float ripple_freq : hint_range(2.0, 30.0) = 10.0;\n"
		+ "void fragment() {\n"
		+ "  float flow = UV.y - TIME * flow_speed;\n"
		+ "  float r1 = sin(flow * ripple_freq) * 0.5 + 0.5;\n"
		+ "  float r2 = cos(flow * ripple_freq * 0.63 + UV.x * 6.2832) * 0.5 + 0.5;\n"
		+ "  float shimmer = r1 * 0.6 + r2 * 0.4;\n"
		+ "  vec3 deep = water_color.rgb * 0.45;\n"
		+ "  vec3 bright = water_color.rgb * 1.20;\n"
		+ "  ALBEDO = mix(deep, bright, shimmer);\n"
		+ "  ALPHA = water_color.a;\n"
		+ "  ROUGHNESS = 0.03;\n"
		+ "  SPECULAR = 0.98;\n"
		+ "}\n"
	)
	var sm := ShaderMaterial.new()
	sm.shader = stream_shader
	_stream_mat = sm

	var splash_shader := Shader.new()
	splash_shader.code = (
		"shader_type spatial;\n"
		+ "render_mode blend_add, depth_draw_never, cull_disabled, unshaded;\n"
		+ "uniform vec4 splash_color : source_color = vec4(0.65, 0.88, 1.0, 0.35);\n"
		+ "uniform float ring_speed : hint_range(0.5, 6.0) = 1.8;\n"
		+ "void fragment() {\n"
		+ "  vec2 uv = UV - 0.5;\n"
		+ "  float d = length(uv) * 2.0;\n"
		+ "  float ring = sin(d * 14.0 - TIME * ring_speed * 6.2832) * 0.5 + 0.5;\n"
		+ "  float fade = smoothstep(1.0, 0.1, d);\n"
		+ "  ALBEDO = splash_color.rgb;\n"
		+ "  ALPHA = ring * fade * splash_color.a;\n"
		+ "}\n"
	)
	var spm := ShaderMaterial.new()
	spm.shader = splash_shader
	_splash_mat = spm

	# Pool — flat disc that grows as volume accumulates; no animation needed
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.30, 0.55, 0.75, 0.72)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.roughness = 0.05
	pm.metallic_specular = 0.90
	_pool_mat = pm

	set_process(true)

	for spec in param_specs():
		set_param(String(spec["key"]), float(spec["default"]))

func set_param(key: String, value: float) -> void:
	_pool_volume_m3 = 0.0
	match key:
		"pipe_diameter":
			_pipe_diameter = value
			if _pipe_mesh and _pipe_mesh.mesh is CylinderMesh:
				var c := _pipe_mesh.mesh as CylinderMesh
				c.top_radius    = value * 0.5
				c.bottom_radius = value * 0.5
			_rebuild_stream()
		"pipe_angle":
			_pipe_angle = value
			_apply_angle()
			_rebuild_stream()
		"water_velocity":
			_water_velocity = value
			_rebuild_stream()

func _process(delta: float) -> void:
	if _pool_mi == null:
		return
	_pool_volume_m3 += _flow_m3s() * delta
	# Pool radius from V = pi * r^2 * depth  ->  r = sqrt(V / (pi * depth))
	var r := sqrt(_pool_volume_m3 / (PI * POOL_DEPTH_M))
	r = minf(r, POOL_MAX_R)
	var disc := CylinderMesh.new()
	disc.top_radius    = r
	disc.bottom_radius = r
	disc.height        = 0.001
	disc.radial_segments = 32
	disc.rings = 1
	_pool_mi.mesh = disc
	_pool_mi.position = Vector3(_pool_hit.x, FLOOR_Y + 0.004, _pool_hit.z)
	_pool_mi.material_override = _pool_mat

func _apply_angle() -> void:
	if _assembly == null:
		return
	var ang := deg_to_rad(_pipe_angle)
	var fwd := Vector3(cos(ang), -sin(ang), 0.0).normalized()
	var right := Vector3.UP.cross(fwd)
	if right.length() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	var up := fwd.cross(right).normalized()
	_assembly.transform.basis = Basis(right, up, fwd)

func _arc_points() -> Array:
	var pts : Array = []
	if _water_velocity < 0.1:
		return pts
	var ang := deg_to_rad(_pipe_angle)
	var fwd := Vector3(cos(ang), -sin(ang), 0.0).normalized()
	var mouth := Vector3(0.0, MOUTH_HEIGHT, -0.6) + fwd * 0.05
	var v0 := _water_velocity
	var dt := 3.0 / float(ARC_STEPS)
	for i in range(ARC_STEPS + 1):
		var t := float(i) * dt
		var pos := mouth + fwd * (v0 * t) + Vector3(0.0, -0.5 * GRAVITY * t * t, 0.0)
		pts.append(pos)
		if pos.y <= FLOOR_Y:
			break
	return pts

func _rebuild_stream() -> void:
	if _stream_mi == null:
		return
	var pts := _arc_points()
	if pts.size() < 2:
		_stream_mi.mesh = null
		if _splash_mi:
			_splash_mi.mesh = null
		return
	var n := pts.size()
	var r0 := _pipe_diameter * 0.5
	var v0 := _water_velocity
	var ang := deg_to_rad(_pipe_angle)
	var fwd := Vector3(cos(ang), -sin(ang), 0.0).normalized()
	var dt := 3.0 / float(ARC_STEPS)

	var tangents : Array = []
	for i in range(n):
		var tan := Vector3.ZERO
		if i == 0:
			tan = (pts[1] - pts[0]).normalized()
		elif i == n - 1:
			tan = (pts[i] - pts[i - 1]).normalized()
		else:
			tan = (pts[i + 1] - pts[i - 1]).normalized()
		tangents.append(tan)

	var rights : Array = []
	var r_seed : Vector3 = tangents[0].cross(Vector3.UP)
	if r_seed.length_squared() < 0.001:
		r_seed = tangents[0].cross(Vector3.RIGHT)
	rights.append(r_seed.normalized())
	for i in range(1, n):
		var tc : Vector3 = tangents[i]
		var rp : Vector3 = rights[i - 1]
		rp = rp - tc * rp.dot(tc)
		if rp.length_squared() < 0.0001:
			rp = tc.cross(Vector3.UP)
		rights.append(rp.normalized())

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(n):
		var th : Vector3 = tangents[i]
		var ri : Vector3 = rights[i]
		var up : Vector3 = th.cross(ri).normalized()
		var t_sec := float(i) * dt
		var v_t := (fwd * v0 + Vector3(0.0, -GRAVITY * t_sec, 0.0)).length()
		var r_here := r0 * sqrt(v0 / maxf(v_t, v0 * 0.1))
		r_here = clampf(r_here, r0 * 0.30, r0)
		var v_norm := float(i) / float(n - 1)
		for j in range(TUBE_SIDES):
			var theta := float(j) / float(TUBE_SIDES) * TAU
			var nrm : Vector3 = (ri * cos(theta) + up * sin(theta)).normalized()
			st.set_normal(nrm)
			st.set_uv(Vector2(float(j) / float(TUBE_SIDES), v_norm))
			st.add_vertex(pts[i] + nrm * r_here)

	for i in range(n - 1):
		for j in range(TUBE_SIDES):
			var a := i * TUBE_SIDES + j
			var b := i * TUBE_SIDES + (j + 1) % TUBE_SIDES
			var c := (i + 1) * TUBE_SIDES + j
			var d := (i + 1) * TUBE_SIDES + (j + 1) % TUBE_SIDES
			st.add_index(a); st.add_index(b); st.add_index(d)
			st.add_index(a); st.add_index(d); st.add_index(c)

	_stream_mi.mesh = st.commit()
	_stream_mi.material_override = _stream_mat

	var hit : Vector3 = pts[n - 1]
	_pool_hit = hit
	var disc := CylinderMesh.new()
	var sr := r0 * 2.2 + 0.10
	disc.top_radius    = sr
	disc.bottom_radius = sr
	disc.height        = 0.001
	disc.radial_segments = 24
	disc.rings = 1
	_splash_mi.mesh     = disc
	_splash_mi.position = Vector3(hit.x, FLOOR_Y + 0.003, hit.z)
	_splash_mi.material_override = _splash_mat
