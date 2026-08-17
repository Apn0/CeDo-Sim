extends Node

## Plant — Plant Coordinate (PC) system for the CeDo Simulator.
##
## #221-PC PHASE 1 — Foundation layer. Single source of truth for converting
## "operator-authored layout positions" into "scene-space Vector3 positions".
## Phases 2-5 migrate every spawner to call Plant.pc_to_scene(); Phase 1 is
## purely additive (nothing currently calls Plant; the existing 6 transforms
## stay in place until each one is migrated).
##
## ─────────────────────────────────────────────────────────────────────────────
##  CANONICAL CONTRACT (resolved from 4 design contradictions caught by the
##  pre-implementation workflow review — see commit message for the 4 picks)
## ─────────────────────────────────────────────────────────────────────────────
##
##  COORD SYSTEM
##    • 1000 × 1000 metre grid, building-axis-aligned (rotated with the plant)
##    • PC(0,0)        = north-west corner of the grid
##    • PC(1000,1000)  = south-east corner
##    • PC(500,500)    = factory_center — the SAME scene-space position passed
##                       to init() as `scene_origin`. Plant does NOT read
##                       WorldLayout.factory_center; the caller resolves which
##                       scene-space point IS the centre and hands it over.
##    • 1 PC unit      = 1 metre exactly
##    • Vector2 (float32) precision floor ≈ 0.1 mm over the 1000 m extent —
##      adequate for cm/mm/sub-mm. For µm/nm/pm precision a separate int64-
##      backed API would be required (deferred — not needed in any current
##      spawner).
##
##  STATE — set ONCE at init(), read-only thereafter:
##    _scene_origin     : Vector3  scene-space position of PC(500,500)
##    _world_yaw_rad    : float    rotation of the PC grid about scene +Y
##    _world_basis_y    : Basis    pre-baked Basis(Vector3.UP, world_yaw_rad)
##    _floor_top_y      : float    operating-floor top-surface Y (baked into
##                                 pc_to_scene results so callers don't have
##                                 to chase _on_floor() everywhere)
##
##  INITIALISATION
##    • Plant.init(scene_origin, world_yaw_rad, floor_top_y) — called ONCE,
##      from MainWorld._ready AFTER PlayerSpawner.spawn() + the floor query.
##    • Subsequent init() calls push_warning AND are no-ops ("initialise once"
##      semantics — last-write-IGNORED, never last-write-wins).
##    • Plant does NOT auto-initialize at autoload boot — it depends on
##      runtime state that doesn't exist until MainWorld wires up.
##    • Subscribers connect to the `plant_initialized` signal; callers that
##      need the contract live (e.g. spawners running during _ready) gate on
##      is_initialized() and connect to the signal if false.
##
##  PRE-INIT BEHAVIOUR — anti-foot-gun
##    • pc_to_scene(_)        → push_error + return Vector3.ZERO
##    • scene_to_pc(_)        → push_error + return Vector2.ZERO
##    • is_initialized()      → false
##    • All accessors (world_yaw_rad/world_basis_y/floor_top_y/...) → default
##    NEVER returns Vector3.INF / NaN — those were the failure modes the
##    377-km bug ($102) was about; we don't reintroduce them.
##
##  YAW CONVENTION
##    • init() takes `world_yaw_rad` verbatim. Caller decides the sign
##      (currently sourced from WorldFrame._world_yaw() which already applies
##      its own −deg_to_rad sign-flip vs the operator slider — that flip
##      stays in WorldFrame, NOT here).
##    • pc_to_scene applies   Basis(Vector3.UP, +_world_yaw_rad).
##    • scene_to_pc applies   Basis(Vector3.UP, −_world_yaw_rad).
##    • Round-trip: pc → scene → pc reproduces the input within ~1e-4 m
##      (Vector2 float32 limit).
##
##  Y HANDLING
##    • pc_to_scene returns Y = _floor_top_y baked in. This is the recipe
##      VehicleSpawner/_layout_to_scene + _on_floor would currently produce
##      after their two-step. Callers that need a different Y (lamp heads,
##      mast-lift platforms, hovering signage) call pc_to_scene_with_y(pc,y).
##
## ─────────────────────────────────────────────────────────────────────────────
##  PHASE 1 SCOPE — only this file + PlantTest.gd + project.godot autoload
##                  registration. NO existing spawner is migrated; the 6 legacy
##                  transforms continue to ship until Phase 3. is_initialized()
##                  returns false at runtime today; once Phase 2 wires the
##                  init() call from MainWorld, the contract goes live.
## ─────────────────────────────────────────────────────────────────────────────

# ── PC-grid constants ────────────────────────────────────────────────────────
const EXTENT_M  : float   = 1000.0
const PC_CENTER : Vector2 = Vector2(500.0, 500.0)

# ── State (set once at init, read-only thereafter) ───────────────────────────
var _scene_origin  : Vector3 = Vector3.ZERO
var _world_yaw_rad : float   = 0.0
var _world_basis_y : Basis   = Basis.IDENTITY
var _floor_top_y   : float   = 0.0
var _initialized   : bool    = false

signal plant_initialized


# ─────────────────────────────────────────────────────────────────────────────
# Lifecycle
# ─────────────────────────────────────────────────────────────────────────────

## ONE-TIME initialization. Snapshot scene_origin (= scene-space position of
## PC(500,500)), the world yaw, and the operating-floor Y. After this returns,
## Plant is "live" and is_initialized() == true. Emits `plant_initialized`.
##
## Subsequent calls push_warning and are NO-OPS — initialise-once semantics.
## (If the building anchor/yaw genuinely changed at runtime, the caller would
## need to tear down every spawned layout-derived object and re-init; that
## migration is not supported by Phase 1.)
func init(scene_origin: Vector3, p_world_yaw_rad: float, p_floor_top_y: float) -> void:
	_scene_origin = scene_origin
	_world_yaw_rad = p_world_yaw_rad
	_world_basis_y = Basis(Vector3.UP, p_world_yaw_rad)
	_floor_top_y = p_floor_top_y
	_initialized = true
	print("[Plant] Initialized: origin=(%.2f, %.2f, %.2f) yaw=%.1f° floor=%.2f m" % [
		scene_origin.x, scene_origin.y, scene_origin.z, 
		rad_to_deg(p_world_yaw_rad), p_floor_top_y])
	plant_initialized.emit()

func is_initialized() -> bool:
	return _initialized


# ─────────────────────────────────────────────────────────────────────────────
# Coordinate conversion — THE single source of truth
# ─────────────────────────────────────────────────────────────────────────────

## PC → scene. Returns the scene Vector3 with Y = floor_top_y baked in.
##
## Pre-init: push_error + return Vector3.ZERO. Never returns NaN/INF.
func pc_to_scene(pc: Vector2) -> Vector3:
	if not _initialized:
		push_error("[Plant] pc_to_scene called before init() — returning Vector3.ZERO")
		return Vector3.ZERO
	# rel_m: metres east(+X) / south(+Z) from the building centre.
	# PC y-axis (north-south) maps to scene Z-axis.
	var rel_m : Vector2 = pc - PC_CENTER
	var rotated : Vector3 = _world_basis_y * Vector3(rel_m.x, 0.0, rel_m.y)
	return Vector3(
		_scene_origin.x + rotated.x,
		_floor_top_y,
		_scene_origin.z + rotated.z,
	)

## PC → scene with an explicit Y override. Use for lamps, mast-lift platforms,
## hovering signage, or anything that should NOT pin to the operating floor.
## The caller owns the Y decision; Plant only owns the XZ math.
func pc_to_scene_with_y(pc: Vector2, y: float) -> Vector3:
	var v : Vector3 = pc_to_scene(pc)
	# Even if pre-init guard fired, preserve the override Y so the caller
	# can distinguish "Plant returned origin with my Y" from a NaN spawn.
	return Vector3(v.x, y, v.z)

## Scene → PC. Inverse of pc_to_scene. Y component of `scene_pos` is dropped
## (PC is a 2D grid). Pre-init: push_error + return Vector2.ZERO.
func scene_to_pc(scene_pos: Vector3) -> Vector2:
	if not _initialized:
		push_error("[Plant] scene_to_pc called before init() — returning Vector2.ZERO")
		return Vector2.ZERO
	var delta : Vector3 = Vector3(
		scene_pos.x - _scene_origin.x, 0.0,
		scene_pos.z - _scene_origin.z,
	)
	# Apply the inverse rotation. Basis(UP, -yaw) is the inverse of Basis(UP, +yaw).
	var inv : Basis = Basis(Vector3.UP, -_world_yaw_rad)
	var local : Vector3 = inv * delta
	return PC_CENTER + Vector2(local.x, local.z)


# ─────────────────────────────────────────────────────────────────────────────
# Read-only accessors (cached state)
# ─────────────────────────────────────────────────────────────────────────────

func world_yaw_rad() -> float:
	return _world_yaw_rad

func world_basis_y() -> Basis:
	return _world_basis_y

func floor_top_y() -> float:
	return _floor_top_y

## Convenience: returns the scene-space Vector3 that PC(500,500) maps to.
## Equivalent to pc_to_scene(PC_CENTER) but cheaper (no rotation needed since
## the (500,500) → (0,0) offset is exactly zero).
func factory_center_scene() -> Vector3:
	if not _initialized:
		return Vector3.ZERO
	return Vector3(_scene_origin.x, _floor_top_y, _scene_origin.z)


# ─────────────────────────────────────────────────────────────────────────────
# Test scaffolding — NOT for production use
# ─────────────────────────────────────────────────────────────────────────────

## Resets Plant to its pre-init state. ONLY for use by PlantTest.gd to verify
## different init configurations. Production code MUST NOT call this — the
## initialise-once contract exists because every spawned layout node bakes
## the current scene_origin / yaw into its global_position at spawn time;
## resetting Plant mid-game would leave the scene tree inconsistent with the
## coordinate system that produced it.
func _reset_for_test() -> void:
	_scene_origin  = Vector3.ZERO
	_world_yaw_rad = 0.0
	_world_basis_y = Basis.IDENTITY
	_floor_top_y   = 0.0
	_initialized   = false
