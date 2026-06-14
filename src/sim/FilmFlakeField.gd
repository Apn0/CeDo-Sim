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
	_mm.visible_instance_count = 0
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
	if mat_mode:
		_build_sinkers()

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
	# Heavies: more dirt → more sinkers falling out of the raft (mat mode only).
	if mat_mode and _sk_mm != null:
		_sk_visible = int(round(SINKER_MAX * clampf(contam01, 0.0, 1.0)))
		if _sk_mat != null:
			_sk_mat.albedo_color = Color(1, 1, 1).lerp(Color(0.6, 0.55, 0.45), clampf(moisture01, 0.0, 1.0))

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

func _process(delta: float) -> void:
	if _mm == null:
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
	var y := surface_y - _dunk[i] * dunk_depth
	var b := Basis(Vector3.UP, _spin[i])
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
func flake_local_pos(i: int) -> Vector3:
	if i < 0 or i >= flake_count:
		return Vector3.ZERO
	return Vector3(_px[i], surface_y - _dunk[i] * dunk_depth, _pz[i])

func dunk_amount(i: int) -> float:
	return _dunk[i] if i >= 0 and i < flake_count else 0.0
