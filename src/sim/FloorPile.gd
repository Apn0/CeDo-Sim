extends Node3D
class_name FloorPile

## A bounded floor zone (e.g. a corner of the wash hall) that accumulates loose
## material when nearby bins overflow or when LineFlow can't route a stream to
## any bin. The pile spreads with an angle of repose ~33° — a cone whose radius
## and height grow with mass.
##
## When the pile's BASE RADIUS would exceed `max_radius_m`, additional mass is
## rejected (the operator now has a real housekeeping problem: a pile that's
## blocking lanes / machine intakes / safety zones, fitting your spec's "access
## clearance" failure mode).
##
## Pure value model — visualization is one CylinderMesh child whose cone shape
## (top_radius=0) is sized each frame from `mass_kg / density_kg_m3`.

signal fill_changed(fraction: float)
signal blocked

@export var max_radius_m   : float = 3.0         # how far the pile is allowed to spread
@export var angle_repose   : float = 33.0        # degrees from horizontal
@export var pile_color     : Color = Color(0.42, 0.40, 0.36)
## P6 (2026-09-23): false = a SOFT mound with no collider. Used for the lump
## spill that heaps around a Lumpenwagen's base: a StaticBody3D growing inside
## a RigidBody3D cart's footprint ejects the cart, so that mound must stay
## walkable. Everything else (chute reject, #159) keeps the solid default.
@export var solid          : bool  = true

var mass_kg              : float = 0.0
var density_kg_m3        : float = 200.0
var _last_frac           : float = -1.0
var _mesh                : MeshInstance3D = null

# #159 — a real SOLID body grown with the cone, so you can't walk or drive
# through the pile. A StaticBody3D child carries a CylinderShape3D sized to the
# mound each update; it's disabled while the pile is empty so an unfilled zone
# isn't a phantom collider.
var _body   : StaticBody3D = null
var _col    : CollisionShape3D = null
var _cshape : CylinderShape3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("floor_pile")
	_build_mesh()
	_build_collision()

func _build_mesh() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.name = "PileMound"
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.0
	cyl.bottom_radius = 0.5
	cyl.height = 0.001
	cyl.radial_segments = 18
	_mesh.mesh = cyl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = pile_color
	mat.roughness = 0.95
	_mesh.material_override = mat
	_mesh.visible = false
	add_child(_mesh)

## Solid collider for the pile (#159). Layer 1 = the world/static layer the
## player capsule and the vehicles collide against, so the mound stops them.
func _build_collision() -> void:
	_body = StaticBody3D.new()
	_body.name = "PileBody"
	_body.collision_layer = 1
	_body.collision_mask = 0
	add_child(_body)
	_col = CollisionShape3D.new()
	_cshape = CylinderShape3D.new()
	_cshape.radius = 0.5
	_cshape.height = 0.02
	_col.shape = _cshape
	_col.disabled = true        # nothing to collide with until material lands
	_body.add_child(_col)

# =============================================================================
# API — bins call add() when their own overflow_budget is exhausted
# =============================================================================
## Add `kg` of material with `density`. Returns what could NOT be accepted
## (because the pile's max_radius_m is already reached). The caller should treat
## that as a "blocked" condition — the place is full.
func add(kg: float, density: float) -> float:
	if kg <= 0.0:
		return 0.0
	# Blend density mass-weighted so a heavy pile doesn't get "reset" by a light
	# top-up (e.g. coarse film falling on top of sludge keeps the average sane).
	if mass_kg > 0.0:
		density_kg_m3 = (density_kg_m3 * mass_kg + density * kg) / (mass_kg + kg)
	else:
		density_kg_m3 = density if density > 0.0 else 200.0
	# Compute the new radius if we accepted everything; if it'd exceed
	# max_radius_m, take only what fits.
	var max_vol := (PI * max_radius_m * max_radius_m * max_radius_m * tan(deg_to_rad(angle_repose))) / 3.0
	var cur_vol := mass_kg / density_kg_m3
	var room_vol := maxf(0.0, max_vol - cur_vol)
	var room_kg := room_vol * density_kg_m3
	var accepted := minf(kg, room_kg)
	mass_kg += accepted
	_update_visual()
	var refused := kg - accepted
	if refused > 0.0:
		emit_signal("blocked")
	return refused

func clear() -> float:
	var was := mass_kg
	mass_kg = 0.0
	density_kg_m3 = 200.0
	_update_visual()
	return was

## Remove up to `kg` from the pile (one shovel scoop — #154). Returns the mass
## actually lifted, so the shovel can deposit exactly that into a container.
func scoop(kg: float) -> float:
	var removed := minf(maxf(kg, 0.0), mass_kg)
	mass_kg -= removed
	_update_visual()
	return removed

func fill_fraction() -> float:
	var max_vol := (PI * max_radius_m * max_radius_m * max_radius_m * tan(deg_to_rad(angle_repose))) / 3.0
	if max_vol <= 0.0:
		return 0.0
	return (mass_kg / density_kg_m3) / max_vol

func _update_visual() -> void:
	if _mesh == null:
		return
	if mass_kg <= 0.001:
		_mesh.visible = false
		if _col != null:
			_col.disabled = true       # empty zone is not a phantom collider
		return
	var vol := mass_kg / density_kg_m3
	var tan_a := tan(deg_to_rad(angle_repose))
	var r : float = pow(3.0 * vol / (PI * tan_a), 1.0 / 3.0)
	var h : float = r * tan_a
	var cyl := _mesh.mesh as CylinderMesh
	cyl.bottom_radius = r
	cyl.height = h
	_mesh.position = Vector3(0.0, h * 0.5, 0.0)
	_mesh.visible = true
	# Grow the SOLID collider with the cone (#159). A cylinder of the cone's base
	# radius + height: slightly fuller than the cone, but it guarantees you can't
	# walk or drive through the heap (you go around it).
	if _cshape != null:
		_cshape.radius = maxf(r, 0.05)
		_cshape.height = maxf(h, 0.02)
		_col.position = Vector3(0.0, h * 0.5, 0.0)
		_col.disabled = not solid
	var frac := fill_fraction()
	if absf(frac - _last_frac) > 0.01:
		_last_frac = frac
		emit_signal("fill_changed", frac)
