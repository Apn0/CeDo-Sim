extends Node3D
class_name FilmFlakeField

## Reusable "physicalized film" layer — a drift of shredded-film flakes riding a
## surface, with optional DUNK ZONES where a paddle/roller pushes the film under
## (the flotation-tank behaviour the operator described: film floats by and gets
## shoved beneath the surface by the paddles).
##
## Rendered with a MultiMesh so a few hundred flakes cost one draw call. Each
## flake has its own position, spin, colour and dunk-phase; _process drifts them
## downstream (+Z local), wraps them at the far edge, and dips any flake passing
## through a dunk zone below the surface before it bobs back up.
##
## Attach to any wet/transport stage (flotation tank, sink separator, belts) and
## call add_dunk_zone() for each paddle. Purely visual + self-contained — it does
## not yet read the LineFlow throughput (that hook comes with the flow-sim, #145).

@export var flake_count : int   = 140
@export var area        : Vector2 = Vector2(2.0, 6.0)   # local X width × Z length
@export var surface_y   : float = 0.0                    # local Y of the "water" surface
@export var flow_speed  : float = 0.5                    # m/s downstream (+Z)
@export var flake_size  : float = 0.07
@export var dunk_depth  : float = 0.35                   # how far under a paddle pushes film

# Full-spectrum shredded-film palette (clear/silver + the bright bits).
const PALETTE : Array[Color] = [
	Color(0.78, 0.80, 0.82), Color(0.30, 0.45, 0.85), Color(0.82, 0.24, 0.20),
	Color(0.25, 0.62, 0.34), Color(0.88, 0.80, 0.22), Color(0.55, 0.55, 0.57),
	Color(0.85, 0.55, 0.20), Color(0.70, 0.35, 0.75),
]

var _mm        : MultiMesh = null
var _mmi       : MultiMeshInstance3D = null
var _mat       : StandardMaterial3D = null   # tinted live for wet / dirty look (#173)
var _base_flow : float = 0.5                 # the design drift speed (load scales it)
var _px        : PackedFloat32Array = PackedFloat32Array()   # local X per flake
var _pz        : PackedFloat32Array = PackedFloat32Array()   # local Z per flake
var _spin      : PackedFloat32Array = PackedFloat32Array()   # yaw per flake
var _spin_rate : PackedFloat32Array = PackedFloat32Array()
var _dunk      : PackedFloat32Array = PackedFloat32Array()   # 0..1 how deep under right now
var _dunk_zones: Array = []   # Array of {x: float, z: float, r: float}
var _rng_seed  : int = 12345

# =============================================================================
func _ready() -> void:
	add_to_group("film_field")
	_base_flow = flow_speed
	_build()

func _build() -> void:
	var flake := BoxMesh.new()
	flake.size = Vector3(flake_size, flake_size * 0.15, flake_size)   # thin chip
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	flake.material = mat
	_mat = mat
	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_colors = true
	_mm.mesh = flake
	_mm.instance_count = flake_count
	_mmi = MultiMeshInstance3D.new()
	_mmi.multimesh = _mm
	add_child(_mmi)
	# Deterministic pseudo-random init (no Math.random — varies by index).
	_px.resize(flake_count); _pz.resize(flake_count)
	_spin.resize(flake_count); _spin_rate.resize(flake_count)
	_dunk.resize(flake_count)
	for i in flake_count:
		_px[i] = _frand(i * 7 + 1) * area.x - area.x * 0.5
		_pz[i] = _frand(i * 13 + 3) * area.y - area.y * 0.5
		_spin[i] = _frand(i * 5 + 2) * TAU
		_spin_rate[i] = (_frand(i * 11 + 4) - 0.5) * 2.0
		_dunk[i] = 0.0
		_mm.set_instance_color(i, PALETTE[i % PALETTE.size()])
		_write_xform(i)

## Register a paddle/roller dunk zone in LOCAL coords. Film passing through gets
## pushed under the surface.
func add_dunk_zone(local_x: float, local_z: float, radius: float) -> void:
	_dunk_zones.append({"x": local_x, "z": local_z, "r": radius})

## #173 — drive the LOOK of the flakes from the machine's live LineFlow state, so
## what you SEE matches what the baked model COMPUTES. All inputs are 0..1-ish:
##   present01   — how much material is in/through this machine → visible flake count
##   load01      — throughput fraction → drift speed (faster line = faster flakes)
##   moisture01  — 0..1 wetness → darker + glossy sheen
##   contam01    — 0..1 dirt    → brown-shifted tint
## Cheap: one visible-count int + a few material fields per call (no per-instance work).
func set_live_state(load01: float, moisture01: float, contam01: float, present01: float) -> void:
	if _mm == null:
		return
	present01 = clampf(present01, 0.0, 1.0)
	_mm.visible_instance_count = int(round(flake_count * present01))
	flow_speed = _base_flow * (0.25 + clampf(load01, 0.0, 1.25))
	if _mat != null:
		var wet  := clampf(moisture01, 0.0, 1.0)
		var dirt := clampf(contam01, 0.0, 1.0)
		# Dry clean film ≈ white (lets the per-flake palette show); wet darkens to a
		# grey sheen; dirt pulls it brown. albedo_color multiplies the vertex colour.
		var tint := Color(1, 1, 1).lerp(Color(0.55, 0.60, 0.66), wet)
		tint = tint.lerp(Color(0.50, 0.42, 0.30), dirt * 0.7)
		_mat.albedo_color = tint
		_mat.roughness = lerpf(0.75, 0.18, wet)   # wet flake is glossy
		_mat.metallic  = lerpf(0.0, 0.15, wet)

## The visible flake count right now (for tests / debugging).
func visible_count() -> int:
	return _mm.visible_instance_count if _mm != null else 0

func _process(delta: float) -> void:
	if _mm == null:
		return
	var half_z := area.y * 0.5
	for i in flake_count:
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

## Compose the instance transform for flake i (position incl. dunk dip + spin).
func _write_xform(i: int) -> void:
	var y := surface_y - _dunk[i] * dunk_depth
	var b := Basis(Vector3.UP, _spin[i])
	# Tilt the flake nose-down while it's being dunked so it reads as "pushed under".
	if _dunk[i] > 0.01:
		b = b * Basis(Vector3.RIGHT, _dunk[i] * 0.8)
	_mm.set_instance_transform(i, Transform3D(b, Vector3(_px[i], y, _pz[i])))

## Deterministic 0..1 hash-ish value from an int (avoids Math.random).
func _frand(n: int) -> float:
	var x := (n * 1103515245 + 12345 + _rng_seed) & 0x7fffffff
	return float(x % 10000) / 10000.0

# ── Queries for tests / debugging ─────────────────────────────────────────────
func flake_local_pos(i: int) -> Vector3:
	if i < 0 or i >= flake_count:
		return Vector3.ZERO
	return Vector3(_px[i], surface_y - _dunk[i] * dunk_depth, _pz[i])

func dunk_amount(i: int) -> float:
	return _dunk[i] if i >= 0 and i < flake_count else 0.0
