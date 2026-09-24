extends Node3D
class_name FilmFlakeField

## Reusable "physicalized film" layer — a drift of shredded-film flakes riding a
## surface, with optional DUNK ZONES where a paddle/roller pushes the film under
## (the transport-roller behaviour on belts / sink separators).
##
## Rendered with a MultiMesh so a few hundred flakes cost one draw call. Each
## flake has its own position, spin, colour and dunk-phase; _process drifts them
## downstream (+Z local), wraps them at the far edge, and dips any flake passing
## through a dunk zone below the surface before it bobs back up.
##
## MAT MODE (#82) — a flotation tank is the OPPOSITE of a dunk: clean LDPE floats
## as a packed mat on the water surface and is skimmed off the top at the outlet,
## while heavies (PET/sand) sink to the floor. Turn on set_mat_mode(true) to make
## the flakes a cohesive, surface-pinned raft (no dunk) that fades/culls as it
## reaches the +Z outlet, plus a cheap SINKER sub-stream of darker chips that fall
## to the tank floor and despawn (count driven by contamination). mat_mode DEFAULTS
## OFF so every other machine using FilmFlakeField is unaffected.
##
## Attach to any wet/transport stage (flotation tank, sink separator, belts) and
## call add_dunk_zone() for each paddle (non-mat mode), or set_mat_mode(true) for a
## float tank. Purely visual + self-contained. Density is driven from the machine's
## live LineFlow state via set_live_state() (#173).

@export var flake_count : int   = 140
@export var area        : Vector2 = Vector2(2.0, 6.0)   # local X width × Z length
@export var surface_y   : float = 0.0                    # local Y of the "water" surface
@export var flow_speed  : float = 0.5                    # m/s downstream (+Z)
@export var flake_size  : float = 0.07
@export var dunk_depth  : float = 0.35                   # how far under a paddle pushes film

# ── BELT MODE (P1, 2026-09-23) ────────────────────────────────────────────────
## A conveyor deck instead of a water surface. Flakes ride ON TOP of a BED whose
## depth is derived, never drawn from a constant: kg per metre of belt is what
## the sim moves (LineFlow's `thru`) over the speed the deck moves it at, and
## depth = kg/m ÷ (bulk density × bed width).
##
## The bed is drawn the way the operator asked (2026-09-23: "it should be
## flakes only — but is that too heavy? Then use the method Gold Mining
## Simulator uses for the soil, with film as the texture"): a HEAP mesh —
## rounded across, lumpy along, unit height scaled to the live depth — wearing
## a procedural film texture (cellular noise coloured in the operator's shares,
## normal-mapped, scrolling downstream), and a DENSE flake layer on top that
## costs the CPU nothing: instance transforms are written once, and a vertex
## shader scrolls each flake along the deck (wrapping at the end), lifts it by
## the live bed depth plus its own jitter, and tints it wet or dirty. Everything
## dynamic is a handful of uniforms per frame, so a belt carries ~120 flakes
## per m² of bed where the CPU-animated raft affords 140 in total.
##
## Operator 2026-09-23, from memory of the Geleen belts: sizes are mixed ("from
## small flake to long strips"); colour is mostly white/translucent, then blue
## in many shades, then every other colour, black rarest; the bed varies per
## belt — the 3A/3B intake belts carry about twice line 1's material at 1.5×
## the speed, the compactorband is "heaped, 20 cm or more" and creeps at ~4 cm/s.
## BED_FULL_M is that heaped figure: the depth at which every flake is visible.
## A stopped deck HOLDS its bed (material on a stopped belt stays where it is);
## a moving one slews at one belt-full per transit time, uniform along the
## deck (a batch's leading edge is not modelled).
var belt_mode : bool = false
@export var bed_bulk_density : float = 180.0   # kg/m³ of loose material on the deck — set per stage by the builder
const BED_FULL_M  : float = 0.20               # operator: "heaped, 20 cm or more" = a full belt
const BED_MIN_M   : float = 0.002              # below this the deck is bare (no heap, no flakes)
const HEAP_TILE_M : float = 0.5                # the film texture repeats every 0.5 m along the deck
var _bed_kgpm   : float = 0.0                  # kg per metre of belt, slewed in set_belt_state
var _bed_depth  : float = 0.0                  # metres, derived from _bed_kgpm
var _belt_speed : float = 0.0                  # live deck speed the bed moves at (0 = stopped)
var _scroll     : float = 0.0                  # metres the bed has travelled, wrapped at area.y
var _lift       : PackedFloat32Array = PackedFloat32Array()   # 0..1 per flake: height jitter on the bed top
var _flake_shader_mat : ShaderMaterial = null  # belt mode: the GPU-scrolled flake material
var _heap       : MeshInstance3D = null
var _heap_mat   : StandardMaterial3D = null
static var _bed_albedo_tex : Texture2D = null  # the film texture, shared by every field
static var _bed_normal_tex : Texture2D = null

const BELT_FLAKE_SHADER : String = """
shader_type spatial;
render_mode cull_disabled, world_vertex_coords;
// The field's +Z (downstream) and +Y (deck normal) in WORLD space — refreshed
// by the node whenever its transform changes.
uniform vec3 belt_axis = vec3(0.0, 0.0, 1.0);
uniform vec3 belt_up = vec3(0.0, 1.0, 0.0);
uniform float belt_len = 6.0;      // area.y: flakes wrap at +/- belt_len / 2
uniform float scroll = 0.0;        // metres travelled downstream (the node wraps it)
uniform float bed_depth = 0.0;     // the live bed depth the flakes ride on
uniform vec4 tint : source_color = vec4(1.0);
uniform float rough = 0.62;
uniform float metal = 0.0;
void vertex() {
	float base_z = INSTANCE_CUSTOM.x;
	float lift = INSTANCE_CUSTOM.y;
	float half_len = belt_len * 0.5;
	float z = mod(base_z + scroll + half_len, belt_len) - half_len;
	VERTEX += belt_axis * (z - base_z) + belt_up * (bed_depth + lift * (0.02 + 0.25 * bed_depth));
}
void fragment() {
	ALBEDO = COLOR.rgb * tint.rgb;
	ROUGHNESS = rough;
	METALLIC = metal;
}
"""

# Full-spectrum shredded-film palette (clear/silver + the bright bits).
const PALETTE : Array[Color] = [
	Color(0.78, 0.80, 0.82), Color(0.30, 0.45, 0.85), Color(0.82, 0.24, 0.20),
	Color(0.25, 0.62, 0.34), Color(0.88, 0.80, 0.22), Color(0.55, 0.55, 0.57),
	Color(0.85, 0.55, 0.20), Color(0.70, 0.35, 0.75),
]
# Heavies that sink: dark, dirty PET/PVC/sand chips (#82 sinker sub-stream).
const SINKER_PALETTE : Array[Color] = [
	Color(0.22, 0.20, 0.18), Color(0.28, 0.26, 0.22), Color(0.18, 0.22, 0.26),
	Color(0.30, 0.24, 0.20),
]
# Operator 2026-09-23, colour ORDER of the film stream: white/translucent, then
# blue (a variety of shades), then all other colours, black least. The shares
# are that ordering made numeric — a stated reading of "more … then … least",
# not a measured count; the 2026-07-20 photos agree on the white majority.
const COLOUR_SHARE_WHITE : float = 0.68
const COLOUR_SHARE_BLUE  : float = 0.16
const COLOUR_SHARE_OTHER : float = 0.13     # the remaining 0.03 is black
const BLUES : Array[Color] = [
	Color(0.30, 0.45, 0.85), Color(0.48, 0.64, 0.92), Color(0.16, 0.28, 0.62),
	Color(0.36, 0.70, 0.90),
]
const OTHERS : Array[Color] = [
	Color(0.82, 0.24, 0.20), Color(0.25, 0.62, 0.34), Color(0.88, 0.80, 0.22),
	Color(0.85, 0.55, 0.20), Color(0.70, 0.35, 0.75),
]
const BLACK : Color = Color(0.11, 0.11, 0.12)

var _mm        : MultiMesh = null
var _mmi       : MultiMeshInstance3D = null
var _mat       : StandardMaterial3D = null   # tinted live for wet / dirty look (#173)
var _base_flow : float = 0.5                 # the design drift speed (load scales it)
var _px        : PackedFloat32Array = PackedFloat32Array()   # local X per flake
var _pz        : PackedFloat32Array = PackedFloat32Array()   # local Z per flake
var _spin      : PackedFloat32Array = PackedFloat32Array()   # yaw per flake
var _spin_rate : PackedFloat32Array = PackedFloat32Array()
var _dunk      : PackedFloat32Array = PackedFloat32Array()   # 0..1 how deep under right now
# Per-flake pose/shape variation (see _build) — shredded film is never uniform.
var _tilt      : PackedFloat32Array = PackedFloat32Array()   # pitch per flake
var _roll      : PackedFloat32Array = PackedFloat32Array()   # roll per flake
var _aspect    : PackedFloat32Array = PackedFloat32Array()   # length multiplier
var _gauge     : PackedFloat32Array = PackedFloat32Array()   # overall size multiplier
var _dunk_zones: Array = []   # Array of {x: float, z: float, r: float}
var _rng_seed  : int = 12345
var _rng       : RandomNumberGenerator = RandomNumberGenerator.new()

# ── MAT MODE (#82) ────────────────────────────────────────────────────────────
var mat_mode   : bool  = false               # float-tank raft (set via set_mat_mode)
var _mat_present : float = 1.0               # latest present01 (mat density / fade)

# ── SINKER sub-stream (#82) — heavies that fall to the floor and despawn ───────
const SINKER_MAX : int = 24                  # cheap cap on the heavies count
var _sk_mm     : MultiMesh = null
var _sk_mmi    : MultiMeshInstance3D = null
var _sk_mat    : StandardMaterial3D = null
var _sk_x      : PackedFloat32Array = PackedFloat32Array()
var _sk_z      : PackedFloat32Array = PackedFloat32Array()
var _sk_y      : PackedFloat32Array = PackedFloat32Array()   # current fall height (down from surface)
var _sk_spin   : PackedFloat32Array = PackedFloat32Array()
var _sk_rate   : PackedFloat32Array = PackedFloat32Array()
var floor_y    : float = -1e9                # tank floor (sinkers land here); see set_floor_y
var _sk_visible: int = 0                     # how many sinkers contam wants alive

# =============================================================================
func _ready() -> void:
	add_to_group("film_field")
	_base_flow = flow_speed
	if floor_y < -1e8:
		floor_y = surface_y - 0.6   # sensible default if caller never set a floor
	_build()
	if belt_mode:
		set_notify_transform(true)
		_refresh_axes()

func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and belt_mode:
		_refresh_axes()

## The scrolling shader works in world space: give it the field's downstream
## axis and deck normal. Machines are built at the origin and moved into place
## by the line macro afterwards, hence the transform notification.
func _refresh_axes() -> void:
	if _flake_shader_mat == null or not is_inside_tree():
		return
	var b : Basis = global_transform.basis
	_flake_shader_mat.set_shader_parameter("belt_axis", b.z.normalized())
	_flake_shader_mat.set_shader_parameter("belt_up", b.y.normalized())

func _build() -> void:
	var flake := _build_flake_mesh()
	if belt_mode:
		# GPU-scrolled flakes (BELT_FLAKE_SHADER): per-instance custom data
		# carries the flake's base z and its lift jitter; the transforms are
		# written once and never touched again.
		var sh := Shader.new()
		sh.code = BELT_FLAKE_SHADER
		_flake_shader_mat = ShaderMaterial.new()
		_flake_shader_mat.shader = sh
		_flake_shader_mat.set_shader_parameter("belt_len", maxf(area.y, 0.01))
		flake.surface_set_material(0, _flake_shader_mat)
	else:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		# Shredded LDPE film is translucent, not an opaque chip — the operator photos
		# (2026-07-20, compactor belt before the PCU) show light passing through the
		# curls, which is what makes the mass read white-grey rather than plastic-grey.
		mat.roughness = 0.62
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED    # single-sided folds, seen from both sides
		flake.surface_set_material(0, mat)
		_mat = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.use_custom_data = belt_mode
	_mm.mesh = flake
	_mm.instance_count = flake_count
	_mm.visible_instance_count = 0
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	add_child(_mmi)
	# Deterministic pseudo-random init (no Math.random — varies by index).
	_px.resize(flake_count); _pz.resize(flake_count)
	_spin.resize(flake_count); _spin_rate.resize(flake_count)
	_dunk.resize(flake_count)
	_tilt.resize(flake_count); _roll.resize(flake_count)
	_aspect.resize(flake_count); _gauge.resize(flake_count)
	_lift.resize(flake_count)
	for i in flake_count:
		_px[i] = _frand(i * 7 + 1) * area.x - area.x * 0.5
		_pz[i] = _frand(i * 13 + 3) * area.y - area.y * 0.5
		_spin[i] = _frand(i * 5 + 2) * TAU
		_spin_rate[i] = (_frand(i * 11 + 4) - 0.5) * 2.0
		_dunk[i] = 0.0
		# Per-flake pose + proportions. In the photos no two shreds are alike and
		# almost none lie flat: they sit at every angle, and lengths run from
		# stubby specks to long torn ribbons. A single uniform chip mesh is what
		# made the old field read as "flat squares".
		_tilt[i] = (_frand(i * 17 + 5) - 0.5) * 1.7      # pitch, radians
		_roll[i] = (_frand(i * 19 + 6) - 0.5) * 1.7      # roll, radians
		# Operator 2026-09-23: "mixed sizes" — small flake to long strips. The
		# spread was 0.55-2.65 in length and 0.60-1.45 in size; widened so the
		# longest shred is ~6× the shortest and the biggest ~3× the smallest.
		_aspect[i] = 0.50 + _frand(i * 23 + 7) * 2.70    # length multiplier
		_gauge[i] = 0.55 + _frand(i * 29 + 8) * 1.05     # overall size multiplier
		_lift[i] = _frand(i * 43 + 12)                   # belt mode: where on the bed top it sits
		if belt_mode:
			_px[i] = (_frand(i * 7 + 1) - 0.5) * area.x * 0.94   # inside the heap's flanks
			_mm.set_instance_custom_data(i, Color(_pz[i], _lift[i], 0.0, 0.0))
		_mm.set_instance_color(i, _flake_color(i))
		_write_xform(i)
	if mat_mode:
		_build_sinkers()
	if belt_mode:
		_build_heap()

## The flake mesh: a CRUMPLED SHRED, not a flat chip.
##
## Operator photos 2026-07-20 (compactor conveyor before the PCU, plus a close-up
## of the finished material): shredded film is torn, curled and folded — every
## piece catches light on several faces at once, which is what makes the mass
## read as bright white-grey rather than a bed of grey tiles. The old mesh was
## `BoxMesh(flake_size, flake_size * 0.15, flake_size)`: a flat square, exactly
## the thing he flagged.
##
## Built as three folded ribbons through the same centre at different angles.
## Cheap (18 tris), and because a MultiMesh shares ONE mesh across every instance
## the variety has to come from the per-instance transform — see _build, where
## each flake gets its own tilt, roll, length and size.
func _build_flake_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s : float = flake_size
	# Three ribbons, each folded along its middle so it reads as a curl.
	for r in 3:
		var ang : float = float(r) * (PI / 3.0) + 0.4
		var ca : float = cos(ang)
		var sa : float = sin(ang)
		var w : float = s * (0.30 - 0.06 * float(r))       # ribbons taper
		var l : float = s * (0.62 - 0.10 * float(r))
		var lift : float = s * (0.16 + 0.07 * float(r))    # fold height
		# Ribbon runs along (ca, 0, sa); width across the perpendicular.
		var along := Vector3(ca, 0.0, sa)
		var across := Vector3(-sa, 0.0, ca)
		var a := -along * l + across * w
		var b := -along * l - across * w
		var c := Vector3(0.0, lift, 0.0) + across * w * 0.5
		var d := Vector3(0.0, lift, 0.0) - across * w * 0.5
		var e := along * l + across * w * 0.7
		var f := along * l - across * w * 0.7
		_quad(st, a, b, d, c)     # up-fold
		_quad(st, c, d, f, e)     # down-fold
	st.generate_normals()
	return st.commit()

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

## Colour for flake i — see COLOUR_SHARE_*: the operator's ordering (white,
## then blue, then the rest, black least). Cycling PALETTE evenly, as the
## oldest code did, made the belt look like confetti instead of like film.
func _flake_color(i: int) -> Color:
	match colour_bucket(i):
		"white":
			# Clear/silver film: vary the grey slightly so the mass isn't flat.
			var g : float = 0.70 + _frand(i * 37 + 10) * 0.22
			return Color(g, g + 0.015, g + 0.03)
		"blue":
			return BLUES[int(_frand(i * 41 + 11) * float(BLUES.size())) % BLUES.size()]
		"other":
			return OTHERS[int(_frand(i * 41 + 11) * float(OTHERS.size())) % OTHERS.size()]
	return BLACK

## Which colour class flake i draws from ("white" / "blue" / "other" / "black").
## Deterministic per index; the suite counts these over a large sample.
func colour_bucket(i: int) -> String:
	var pick : float = _frand(i * 31 + 9)
	if pick < COLOUR_SHARE_WHITE:
		return "white"
	if pick < COLOUR_SHARE_WHITE + COLOUR_SHARE_BLUE:
		return "blue"
	if pick < COLOUR_SHARE_WHITE + COLOUR_SHARE_BLUE + COLOUR_SHARE_OTHER:
		return "other"
	return "black"

## Build the (cheap, separate) heavies MultiMesh. Only spun up in mat mode so
## non-flotation users pay nothing.
func _build_sinkers() -> void:
	if _sk_mm != null:
		return
	var chip := BoxMesh.new()
	chip.size = Vector3(flake_size * 0.8, flake_size * 0.8, flake_size * 0.8)   # blocky heavy
	var smat := StandardMaterial3D.new()
	smat.vertex_color_use_as_albedo = true
	smat.roughness = 0.9
	chip.material = smat
	_sk_mat = smat
	_sk_mm = MultiMesh.new()
	_sk_mm.transform_format = MultiMesh.TRANSFORM_3D
	_sk_mm.use_colors = true
	_sk_mm.mesh = chip
	_sk_mm.instance_count = SINKER_MAX
	_sk_mmi = MultiMeshInstance3D.new()
	_sk_mmi.multimesh = _sk_mm
	add_child(_sk_mmi)
	_sk_x.resize(SINKER_MAX); _sk_z.resize(SINKER_MAX); _sk_y.resize(SINKER_MAX)
	_sk_spin.resize(SINKER_MAX); _sk_rate.resize(SINKER_MAX)
	for i in SINKER_MAX:
		_respawn_sinker(i)
		_sk_mm.set_instance_color(i, SINKER_PALETTE[i % SINKER_PALETTE.size()])
		_write_sinker_xform(i)
	_sk_mm.visible_instance_count = 0

## Reset one sinker to just below the surface at a fresh lateral spot.
func _respawn_sinker(i: int) -> void:
	var n := i * 23 + int(_sk_y[i] * 50.0) + 9
	_sk_x[i] = _frand(n * 3 + 1) * area.x - area.x * 0.5
	_sk_z[i] = _frand(n * 5 + 2) * area.y - area.y * 0.5
	_sk_y[i] = 0.0                              # depth below surface (grows as it falls)
	_sk_spin[i] = _frand(n * 7 + 3) * TAU
	_sk_rate[i] = (_frand(n * 11 + 4) - 0.5) * 3.0

## Turn the flotation MAT behaviour on/off. Default OFF — leaves every other
## machine's drift+dunk look untouched. Builds the sinker stream on first enable.
func set_mat_mode(on: bool) -> void:
	mat_mode = on
	if on:
		_dunk_zones.clear()          # a float tank never dunks the film
		if _mm != null and _sk_mm == null:
			_build_sinkers()

## Set the tank-floor local Y where heavies come to rest before despawning. Call
## before/after _ready (it's just a number used by the sinker fall).
func set_floor_y(y: float) -> void:
	floor_y = y

## BELT MODE (P1) — a conveyor deck. Off by default; the belt builders turn it on
## BEFORE the node enters the tree (the flake material is chosen in _build).
## Mutually exclusive with mat mode.
func set_belt_mode(on: bool) -> void:
	belt_mode = on
	if on:
		mat_mode = false
		_dunk_zones.clear()
		if _mm != null and _heap == null:
			_build_heap()

## The heap: a unit-height mesh (y in 0..1) — rounded across (30 % where the
## flanks meet the deck, 100 % on the crest, feet on the deck at ±w/2), lumpy
## along and across (deterministic ±12 % / ±8 %) —
## scaled in Y to the live depth, so nothing is rebuilt at runtime. Normals are
## the profile's own (in unit space; the renderer's inverse-transpose handles
## the Y scale), UV u across and v along in HEAP_TILE_M tiles so the film
## texture keeps its size on every belt.
func _build_heap() -> void:
	if _heap != null:
		return
	# Columns: a foot on the deck at -w/2, the rounded profile over ±0.96 w/2,
	# a foot at +w/2 — so the heap's flanks run down to the deck instead of
	# floating a flank-height above it.
	var nx : int = 8
	var cols : int = nx + 3
	var nz : int = maxi(4, int(round(area.y / 0.6)))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half_w : float = maxf(area.x, 0.001) * 0.5
	for iz in nz + 1:
		var t : float = float(iz) / float(nz)
		var z : float = (t - 0.5) * area.y
		var row_lump : float = 1.0 + 0.12 * (_frand(iz * 31 + 99) - 0.5) * 2.0
		for ic in cols:
			var x : float
			var h : float
			var n : Vector3
			if ic == 0 or ic == cols - 1:
				var side : float = -1.0 if ic == 0 else 1.0
				x = side * half_w
				h = 0.0
				n = Vector3(side, 0.35, 0.0).normalized()
			else:
				var xn : float = (float(ic - 1) / float(nx) - 0.5) * 2.0 * 0.96
				var root : float = sqrt(1.0 - xn * xn)
				var prof : float = 0.30 + 0.70 * root
				var dprof_dxn : float = -0.70 * xn / root
				var lump : float = 1.0 + 0.08 * (_frand(iz * 53 + ic * 7 + 5) - 0.5) * 2.0
				x = xn * half_w
				h = prof * row_lump * lump
				# unit-space normal of y = prof(x): (-dy/dx, 1, 0), dy/dx = dprof/dxn / half_w
				n = Vector3(-dprof_dxn * row_lump * lump / half_w, 1.0, 0.0).normalized()
			st.set_normal(n)
			st.set_uv(Vector2(x / area.x + 0.5, z / HEAP_TILE_M))
			st.add_vertex(Vector3(x, h, z))
	for iz in nz:
		for ic in cols - 1:
			var i0 : int = iz * cols + ic
			var i1 : int = i0 + 1
			var i2 : int = i0 + cols
			var i3 : int = i2 + 1
			st.add_index(i0); st.add_index(i2); st.add_index(i1)
			st.add_index(i1); st.add_index(i2); st.add_index(i3)
	st.generate_tangents()
	var mesh : ArrayMesh = st.commit()
	_bed_textures()
	_heap_mat = StandardMaterial3D.new()
	_heap_mat.albedo_texture = _bed_albedo_tex
	_heap_mat.normal_enabled = true
	_heap_mat.normal_texture = _bed_normal_tex
	_heap_mat.normal_scale = 1.0
	_heap_mat.roughness = 0.75
	_heap_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, _heap_mat)
	_heap = MeshInstance3D.new()
	_heap.name = "BedHeap"
	_heap.mesh = mesh
	_heap.visible = false
	_heap.position = Vector3(0.0, surface_y, 0.0)
	_heap.scale = Vector3(1.0, 0.001, 1.0)
	add_child(_heap)

## The film texture the heap wears, built once for every field: cellular noise
## (each cell one shred, ~5 cm at HEAP_TILE_M) coloured through a constant
## gradient in the operator's shares — white/translucent most, blue next, the
## other colours, black least — and the same cells as a normal map so the
## shred edges catch the light. Procedural: nothing under assets/ is needed.
static func _bed_textures() -> void:
	if _bed_albedo_tex != null:
		return
	# Built synchronously from an Image (NoiseTexture2D generates on a thread
	# and is blank until it finishes — measured 2026-09-23 as a black heap in
	# the first v2 render).
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.cellular_return_type = FastNoiseLite.RETURN_CELL_VALUE
	noise.frequency = 0.045
	noise.seed = 7
	var ramp := Gradient.new()
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	ramp.offsets = PackedFloat32Array([0.0, 0.30, 0.55, 0.66, 0.70, 0.79, 0.82, 0.86, 0.90, 0.95, 0.97, 0.99])
	ramp.colors = PackedColorArray([
		Color(0.74, 0.75, 0.78), Color(0.86, 0.87, 0.90), Color(0.80, 0.81, 0.84),
		Color(0.36, 0.52, 0.85), Color(0.90, 0.91, 0.93), Color(0.50, 0.66, 0.92),
		Color(0.78, 0.79, 0.82), Color(0.80, 0.30, 0.26), Color(0.84, 0.85, 0.88),
		Color(0.30, 0.62, 0.36), Color(0.12, 0.12, 0.13), Color(0.18, 0.30, 0.62),
	])
	var n : int = 256
	var cells : Image = noise.get_seamless_image(n, n)
	var alb := Image.create(n, n, false, Image.FORMAT_RGB8)
	for y in n:
		for x in n:
			var v : float = cells.get_pixel(x, y).r
			# a little within-cell shading so a shred is not one flat tone
			var c : Color = ramp.sample(v)
			var shade : float = 0.92 + 0.08 * fposmod(v * 37.0, 1.0)
			alb.set_pixel(x, y, Color(c.r * shade, c.g * shade, c.b * shade))
	_bed_albedo_tex = ImageTexture.create_from_image(alb)
	var bump : Image = cells.duplicate()
	bump.convert(Image.FORMAT_RF)
	bump.bump_map_to_normal_map(6.0)
	_bed_normal_tex = ImageTexture.create_from_image(bump)

## kg per metre at which the bed is BED_FULL_M deep on this deck.
func belt_full_kg_per_m() -> float:
	return BED_FULL_M * bed_bulk_density * area.x

## Belt-mode drive, called by LineFlow every flow tick (dt = 0.1 s):
##   thru_kgps  — kg/s the sim moved through this belt (nd["thru"])
##   speed_mps  — the deck's live speed (belt_speed meta × spin)
##   moving     — false while the deck is stopped: the bed then HOLDS
##   moisture01 / contam01 — as set_live_state (wet sheen, dirt tint)
## Slew: one belt-full per transit time (length / speed) — a belt cannot fill
## or empty faster than its own length travels.
func set_belt_state(thru_kgps: float, speed_mps: float, moving: bool,
		moisture01: float, contam01: float, dt: float) -> void:
	if _mm == null:
		return
	_belt_speed = maxf(speed_mps, 0.0) if moving else 0.0
	flow_speed = _belt_speed
	if moving:
		var v_eff : float = maxf(speed_mps, 0.02)
		var target : float = maxf(thru_kgps, 0.0) / v_eff
		var transit_s : float = maxf(area.y, 0.1) / v_eff
		var step : float = belt_full_kg_per_m() * maxf(dt, 0.0) / transit_s
		_bed_kgpm = move_toward(_bed_kgpm, target, step)
	_bed_depth = _bed_kgpm / maxf(bed_bulk_density * area.x, 0.001)
	var frac : float = 0.0
	if _bed_depth > BED_MIN_M:
		frac = clampf(0.25 + 0.75 * _bed_depth / BED_FULL_M, 0.0, 1.0)
	var n_vis : int = int(round(float(flake_count) * frac))
	_mm.visible_instance_count = n_vis
	_apply_tint(moisture01, contam01)
	if _flake_shader_mat != null:
		_flake_shader_mat.set_shader_parameter("bed_depth", _bed_depth)
	if _heap != null:
		var show : bool = _bed_depth > BED_MIN_M
		_heap.visible = show
		if show:
			_heap.scale = Vector3(1.0, _bed_depth, 1.0)

func bed_depth_m() -> float:
	return _bed_depth

func bed_kg_per_m() -> float:
	return _bed_kgpm

func bed_kg() -> float:
	return _bed_kgpm * area.y

func belt_speed_mps() -> float:
	return _belt_speed

## Metres the bed has scrolled downstream, wrapped at the deck length (belt mode).
func scroll_m() -> float:
	return _scroll

## Register a paddle/roller dunk zone in LOCAL coords. Film passing through gets
## pushed under the surface. Ignored while in mat mode (a float tank doesn't dunk).
func add_dunk_zone(local_x: float, local_z: float, radius: float) -> void:
	if mat_mode:
		return
	_dunk_zones.append({"x": local_x, "z": local_z, "r": radius})

## #173 — drive the LOOK of the flakes from the machine's live LineFlow state, so
## what you SEE matches what the baked model COMPUTES. All inputs are 0..1-ish:
##   present01   — how much material is in/through this machine → visible flake count
##   load01      — throughput fraction → drift speed (faster line = faster flakes)
##   moisture01  — 0..1 wetness → darker + glossy sheen
##   contam01    — 0..1 dirt    → brown-shifted tint + how many heavies sink (mat mode)
## Cheap: one visible-count int + a few material fields per call (no per-instance work).
func set_live_state(load01: float, moisture01: float, contam01: float, present01: float) -> void:
	if _mm == null:
		return
	present01 = clampf(present01, 0.0, 1.0)
	_mat_present = present01
	# Flotation tank (mat mode) is NEVER visually empty during operation — a real
	# float tank holds standing water + a thin floating mat from the moment it's
	# wetted up, well before kg-level buffer fills. Floor the visible raft so the
	# tank reads as "running" even when LineFlow's buffer hasn't ramped yet.
	# Drift-mode fields (belts, sink separators) keep the old behaviour: empty
	# until material actually arrives.
	var present_eff : float = present01
	if mat_mode and present01 > 0.0:
		present_eff = maxf(present01, 0.45)
	_mm.visible_instance_count = int(round(flake_count * present_eff))
	# In mat mode the raft creeps; otherwise it drifts at the load-scaled design speed.
	if mat_mode:
		flow_speed = _base_flow * (0.15 + clampf(load01, 0.0, 1.0) * 0.5)
	else:
		flow_speed = _base_flow * (0.25 + clampf(load01, 0.0, 1.25))
	_apply_tint(moisture01, contam01)
	# Heavies: more dirt → more sinkers falling out of the raft (mat mode only).
	if mat_mode and _sk_mm != null:
		_sk_visible = int(round(SINKER_MAX * clampf(contam01, 0.0, 1.0)))
		if _sk_mat != null:
			_sk_mat.albedo_color = Color(1, 1, 1).lerp(Color(0.6, 0.55, 0.45), clampf(moisture01, 0.0, 1.0))

## Dry clean film ≈ white (lets the per-flake palette show); wet darkens to a
## grey sheen and goes glossy; dirt pulls it brown. albedo_color multiplies the
## vertex colour. In belt mode the same tint goes to the flake shader and the heap.
func _apply_tint(moisture01: float, contam01: float) -> void:
	var wet  := clampf(moisture01, 0.0, 1.0)
	var dirt := clampf(contam01, 0.0, 1.0)
	var tint := Color(1, 1, 1).lerp(Color(0.55, 0.60, 0.66), wet)
	tint = tint.lerp(Color(0.50, 0.42, 0.30), dirt * 0.7)
	if _mat != null:
		_mat.albedo_color = tint
		_mat.roughness = lerpf(0.75, 0.18, wet)   # wet flake is glossy
		_mat.metallic  = lerpf(0.0, 0.15, wet)
	if _flake_shader_mat != null:
		_flake_shader_mat.set_shader_parameter("tint", tint)
		_flake_shader_mat.set_shader_parameter("rough", lerpf(0.62, 0.18, wet))
		_flake_shader_mat.set_shader_parameter("metal", lerpf(0.0, 0.15, wet))
	if _heap_mat != null:
		_heap_mat.albedo_color = tint
		_heap_mat.roughness = lerpf(0.75, 0.22, wet)

## The visible flake count right now (for tests / debugging).
func visible_count() -> int:
	return _mm.visible_instance_count if _mm != null else 0

## The visible sinker (heavies) count right now (for tests / debugging).
func sinker_count() -> int:
	return _sk_mm.visible_instance_count if _sk_mm != null else 0

## Perf gates — top CPU hog before this patch was every FilmFlakeField iterating
## its full flake_count every frame regardless of visibility, camera distance, or
## whether the machine was even running. With ~80 fields × ~80 flakes that's
## thousands of set_instance_transform RID calls + Basis/Transform3D allocations
## per frame. Now:
##   • Tick at most every TICK_PERIOD_S (~20 Hz) — drift is purely cosmetic.
##   • Skip entirely when the machine is idle (visible_instance_count == 0).
##   • Skip when the camera is > CULL_DIST_M away (off-screen tanks animate nothing).
##   • Loop only the visible_instance_count, not the full flake_count.
const TICK_PERIOD_S : float = 0.05      # 20 Hz
const CULL_DIST_M   : float = 30.0
var _tick_acc       : float = 0.0
# Cost attribution for probes: total microseconds every field spent in _step()
# since the counter was last zeroed. Off unless a probe turns it on.
static var profiling  : bool = false
static var profile_us : int = 0

func _process(delta: float) -> void:
	if not profiling:
		_step(delta)
		return
	var t0 : int = Time.get_ticks_usec()
	_step(delta)
	profile_us += Time.get_ticks_usec() - t0

func _step(delta: float) -> void:
	if _mm == null:
		return
	if belt_mode:
		# The GPU draws and moves the flakes; the node only advances the scroll
		# (two uniform writes per frame). Nothing to do while stopped or bare.
		if _belt_speed <= 0.0 or _mm.visible_instance_count <= 0:
			return
		_scroll = fmod(_scroll + _belt_speed * delta, maxf(area.y, 0.01))
		if _flake_shader_mat != null:
			_flake_shader_mat.set_shader_parameter("scroll", _scroll)
		if _heap_mat != null:
			_heap_mat.uv1_offset = Vector3(0.0, -_scroll / HEAP_TILE_M, 0.0)
		return
	_tick_acc += delta
	if _tick_acc < TICK_PERIOD_S:
		return
	var dt : float = _tick_acc
	_tick_acc = 0.0
	# Idle gate: no visible flakes means LineFlow has starved the unit — nothing
	# to animate, skip the whole iteration.
	if _mm.visible_instance_count <= 0:
		# Sinkers can still animate when contam is high even with no surface raft,
		# so handle them independently below.
		if mat_mode and _sk_mm != null and _sk_visible > 0:
			_process_sinkers(dt)
		return
	# Distance cull: don't burn CPU on tanks the camera can't see. Cheap viewport
	# camera lookup; falls through (animates) if no camera (e.g. headless tests).
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam != null:
		var d2 : float = (cam.global_position - global_position).length_squared()
		if d2 > CULL_DIST_M * CULL_DIST_M:
			return
	if mat_mode:
		_process_mat(dt)
	else:
		_process_drift(dt)
	if mat_mode and _sk_mm != null:
		_process_sinkers(dt)

## Original behaviour: flakes drift downstream and get dunked by paddle zones.
## Iterates visible_instance_count only — invisible flakes are LineFlow-starved
## and don't need a transform write.
func _process_drift(delta: float) -> void:
	var half_z := area.y * 0.5
	var n : int = mini(_mm.visible_instance_count, flake_count)
	for i in n:
		# Drift downstream.
		_pz[i] += flow_speed * delta
		if _pz[i] > half_z:
			# Wrap back to the inlet with a fresh lateral position.
			_pz[i] = -half_z
			_px[i] = _frand(i * 17 + int(_pz[i] * 100.0) + 7) * area.x - area.x * 0.5
		_spin[i] += _spin_rate[i] * delta
		# Dunk logic — if inside any zone, drive _dunk up (sink); else recover.
		var target_dunk := 0.0
		for z in _dunk_zones:
			var dx : float = _px[i] - z["x"]
			var dz : float = _pz[i] - z["z"]
			if dx * dx + dz * dz <= z["r"] * z["r"]:
				target_dunk = 1.0
				break
		_dunk[i] = move_toward(_dunk[i], target_dunk, delta * 3.0)
		_write_xform(i)

## Flotation MAT: flakes are pinned at the surface (no dunk), creep slowly toward
## the +Z outlet as a cohesive raft, and are skimmed (wrap back to the inlet) at
## the far edge. Lateral spread is gently compressed so the raft reads as packed.
func _process_mat(delta: float) -> void:
	var half_z := area.y * 0.5
	var n : int = mini(_mm.visible_instance_count, flake_count)
	for i in n:
		_pz[i] += flow_speed * delta
		if _pz[i] > half_z:
			# Skimmed off at the outlet — recycle to the inlet end.
			_pz[i] = -half_z
			_px[i] = _frand(i * 19 + int(_pz[i] * 100.0) + 5) * area.x - area.x * 0.5
		# Pack toward the centre-line a touch so it looks like a mat, not a scatter.
		_px[i] = move_toward(_px[i], _px[i] * 0.85, delta * 0.05)
		# Mats barely tumble — slow, settled spin.
		_spin[i] += _spin_rate[i] * delta * 0.25
		_dunk[i] = 0.0
		_write_xform(i)

## Heavies fall straight down from just under the surface to the tank floor, then
## despawn + respawn. Only as many as contamination wants are made visible.
func _process_sinkers(delta: float) -> void:
	_sk_mm.visible_instance_count = _sk_visible
	var fall_span : float = maxf(0.05, surface_y - floor_y)
	for i in _sk_visible:
		_sk_y[i] += delta * 0.45                  # sink rate (m/s downward)
		_sk_spin[i] += _sk_rate[i] * delta
		if _sk_y[i] >= fall_span:
			_respawn_sinker(i)                    # landed on the floor → new heavy
		_write_sinker_xform(i)

## Compose the instance transform for flake i (position incl. dunk dip + spin). In
## mat mode flakes pack denser/larger and fade out as they near the outlet.
func _write_xform(i: int) -> void:
	# Belt mode: the base slot on the deck surface — the shader adds the live
	# bed depth and the flake's lift (see _flake_y for the same sum, CPU-side).
	var y : float = surface_y if belt_mode else _flake_y(i)
	# Yaw (drift spin) THEN the flake's own fixed tilt/roll, so each shred keeps
	# its crumpled attitude while the field turns it. Non-uniform scale stretches
	# it along its own length axis — that's what gives the torn-ribbon spread the
	# operator photos show instead of a bed of identical squares.
	var b := Basis(Vector3.UP, _spin[i]) * Basis(Vector3.RIGHT, _tilt[i]) * Basis(Vector3.BACK, _roll[i])
	b = b.scaled(Vector3(_gauge[i], _gauge[i], _gauge[i] * _aspect[i]))
	if mat_mode:
		# Pack the raft denser + a touch larger, then SHRINK to nothing over the last
		# stretch before the +Z outlet so the mat reads as skimmed off the top (a
		# scale-cull — no material transparency needed, stays one cheap draw call).
		var half_z : float = area.y * 0.5
		var z01 : float = clampf((_pz[i] + half_z) / maxf(area.y, 0.001), 0.0, 1.0)
		var skim : float = clampf((1.0 - z01) / 0.18, 0.0, 1.0)   # 1 in the body → 0 at outlet
		b = b.scaled(Vector3(1.35 * skim, 1.0 * skim, 1.35 * skim))
	elif _dunk[i] > 0.01:
		# Tilt the flake nose-down while it's being dunked so it reads as "pushed under".
		b = b * Basis(Vector3.RIGHT, _dunk[i] * 0.8)
	_mm.set_instance_transform(i, Transform3D(b, Vector3(_px[i], y, _pz[i])))

## Compose the transform for sinker i (falling from surface toward floor_y).
func _write_sinker_xform(i: int) -> void:
	var y := surface_y - _sk_y[i]
	var b := Basis(Vector3.UP, _sk_spin[i]) * Basis(Vector3.RIGHT, _sk_spin[i] * 0.5)
	_sk_mm.set_instance_transform(i, Transform3D(b, Vector3(_sk_x[i], y, _sk_z[i])))

## Deterministic 0..1 hash-ish value from an int (avoids Math.random).
func _frand(n: int) -> float:
	_rng.seed = n + _rng_seed
	return _rng.randf()

# ── Queries for tests / debugging ─────────────────────────────────────────────
## Belt mode: the flake's base slot lifted onto the bed, BEFORE the shader's
## downstream scroll (which the CPU does not track per flake).
func flake_local_pos(i: int) -> Vector3:
	if i < 0 or i >= flake_count:
		return Vector3.ZERO
	return Vector3(_px[i], _flake_y(i), _pz[i])

## Local Y of flake i: on the bed top in belt mode (lifted by its own jitter so
## a heap reads lumpy), dunked under the surface otherwise.
func _flake_y(i: int) -> float:
	if belt_mode:
		return surface_y + _bed_depth + _lift[i] * (0.02 + 0.25 * _bed_depth)
	return surface_y - _dunk[i] * dunk_depth

func dunk_amount(i: int) -> float:
	return _dunk[i] if i >= 0 and i < flake_count else 0.0
