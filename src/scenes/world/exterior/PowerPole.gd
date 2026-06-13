extends Node3D
class_name PowerPole

## Wooden utility pole + crossarm + ceramic insulators, with optional wire
## stand-ins running to a neighbour pole. Caller is responsible for placing
## one pole per span endpoint and then calling `build_to(next_pos)` once for
## each outgoing span (so a mid-line pole gets one call; an end pole gets none).
##
## Usage pattern (caller wire-up):
##   var p := PowerPole.new()
##   add_child(p)
##   p.global_position = Vector3(x, ground_y, z)
##   p.build_pole()
##   p.build_to(next_pole_global_position)   # optional, per outgoing span
##
## All geometry is built from primitive meshes with inline StandardMaterial3D —
## no textures, no preloads. `pole_h`, `crossarm_span`, `wire_sag` are exported
## so WorldLayout can tune the look later without editing this script.

@export var pole_h        : float = 8.0
@export var crossarm_span : float = 2.2
@export var wire_sag      : float = 0.4

# Cached materials (built lazily so build_pole / build_to share them).
var _wood_mat      : StandardMaterial3D = null
var _insulator_mat : StandardMaterial3D = null
var _wire_mat      : StandardMaterial3D = null

# Y of the crossarm top surface (where insulator stubs stand).  Filled by build_pole().
var _crossarm_top_y : float = 0.0
# Local-space X offsets of the three insulator tops along the crossarm.
var _insulator_offsets_x : Array = []  # Array[float]
# Short stub height — kept around so build_to() puts wires at the stub tops.
var _stub_h : float = 0.18

func _ready() -> void:
	# Allow the caller to omit build_pole() and still get something visible if
	# the pole is dropped into a scene tree as-is.  Idempotency is guarded by
	# the cached material check below.
	if _wood_mat == null:
		build_pole()

# ── Public API ────────────────────────────────────────────────────────────────

func build_pole() -> void:
	if _wood_mat != null:
		return  # already built
	_ensure_materials()
	_build_pole_shaft()
	_build_crossarm()
	_build_insulators()

func build_to(next_pos: Vector3) -> void:
	if _wood_mat == null:
		push_warning("[PowerPole] build_to() called before build_pole() — building now")
		build_pole()
	_build_wires(next_pos)

# ── Materials ─────────────────────────────────────────────────────────────────

func _ensure_materials() -> void:
	_wood_mat = StandardMaterial3D.new()
	_wood_mat.albedo_color = Color(0.30, 0.22, 0.16)   # creosote-dark pine
	_wood_mat.roughness = 0.92
	_wood_mat.metallic = 0.0
	_insulator_mat = StandardMaterial3D.new()
	_insulator_mat.albedo_color = Color(0.78, 0.78, 0.75)   # light grey ceramic
	_insulator_mat.roughness = 0.55
	_insulator_mat.metallic = 0.0
	_wire_mat = StandardMaterial3D.new()
	_wire_mat.albedo_color = Color(0.05, 0.05, 0.05)    # black insulated wire
	_wire_mat.roughness = 0.80
	_wire_mat.metallic = 0.0

# ── Pole shaft (vertical creosote cylinder) ───────────────────────────────────

func _build_pole_shaft() -> void:
	var shaft := MeshInstance3D.new()
	shaft.name = "PoleShaft"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.13
	cm.bottom_radius = 0.16
	cm.height = pole_h
	shaft.mesh = cm
	shaft.position = Vector3(0.0, pole_h * 0.5, 0.0)
	shaft.material_override = _wood_mat
	add_child(shaft)

# ── Crossarm (horizontal box near the top, oriented along local X) ────────────

func _build_crossarm() -> void:
	var arm_h : float = 0.14
	var arm_d : float = 0.14
	var arm := MeshInstance3D.new()
	arm.name = "Crossarm"
	var bm := BoxMesh.new()
	bm.size = Vector3(crossarm_span, arm_h, arm_d)
	arm.mesh = bm
	# Sit the crossarm just below the top of the pole so the pole pokes up
	# slightly above it (real utility poles do this).
	var arm_centre_y : float = pole_h - 0.5
	arm.position = Vector3(0.0, arm_centre_y, 0.0)
	arm.material_override = _wood_mat
	add_child(arm)
	_crossarm_top_y = arm_centre_y + arm_h * 0.5

# ── Three insulator stubs on top of the crossarm ──────────────────────────────

func _build_insulators() -> void:
	_insulator_offsets_x = [
		-crossarm_span * 0.5 + 0.15,
		0.0,
		 crossarm_span * 0.5 - 0.15,
	]
	for i in _insulator_offsets_x.size():
		var stub := MeshInstance3D.new()
		stub.name = "Insulator_%d" % i
		var cm := CylinderMesh.new()
		cm.top_radius = 0.045
		cm.bottom_radius = 0.055
		cm.height = _stub_h
		stub.mesh = cm
		stub.position = Vector3(_insulator_offsets_x[i], _crossarm_top_y + _stub_h * 0.5, 0.0)
		stub.material_override = _insulator_mat
		add_child(stub)

# ── Wires to the next pole ────────────────────────────────────────────────────

func _build_wires(next_pos: Vector3) -> void:
	# Convert next_pos (assumed global) into this pole's local space so we can
	# parent the wire meshes under self with simple local transforms.
	var next_local : Vector3 = global_transform.affine_inverse() * next_pos
	# The next pole's crossarm is assumed identical to ours — its insulator
	# tops live at (offset_x, _crossarm_top_y + stub_h, 0) in ITS local frame.
	# Without knowing its yaw we approximate by mirroring along the vector
	# from us to next_local: project each insulator offset along the
	# perpendicular axis in the XZ plane.
	var to_next_xz := Vector2(next_local.x, next_local.z)
	if to_next_xz.length() < 0.1:
		push_warning("[PowerPole] build_to(): next_pos coincides with this pole — skipping wires")
		return
	var dir2 : Vector2 = to_next_xz.normalized()
	# Perpendicular in XZ (so insulator offsets along the crossarm map to
	# offsets perpendicular to the wire run direction).  Using the +90° rotation.
	var perp2 := Vector2(-dir2.y, dir2.x)
	var wire_top_y : float = _crossarm_top_y + _stub_h
	for i in _insulator_offsets_x.size():
		var off : float = _insulator_offsets_x[i]
		# Start: our insulator top.  In local space, our crossarm runs along X.
		var start : Vector3 = Vector3(off, wire_top_y, 0.0)
		# End: corresponding insulator top of the next pole.  We assume the
		# next pole is aimed at us so its crossarm runs perpendicular to
		# (next - self) in the XZ plane.
		var end_xz : Vector2 = to_next_xz + perp2 * off
		var end : Vector3 = Vector3(end_xz.x, wire_top_y, end_xz.y)
		_build_one_wire(start, end, i)

func _build_one_wire(start: Vector3, end: Vector3, wire_idx: int) -> void:
	# A sagging wire is approximated by two thin BoxMesh segments meeting at a
	# midpoint that has been dropped by `wire_sag`.  Cheap, readable, and good
	# enough at exterior viewing distance.
	var mid : Vector3 = (start + end) * 0.5 + Vector3(0.0, -wire_sag, 0.0)
	_build_wire_segment(start, mid, wire_idx, 0)
	_build_wire_segment(mid, end, wire_idx, 1)

func _build_wire_segment(a: Vector3, b: Vector3, wire_idx: int, seg_idx: int) -> void:
	var delta : Vector3 = b - a
	var length : float = delta.length()
	if length < 0.01:
		return
	var seg := MeshInstance3D.new()
	seg.name = "Wire_%d_%d" % [wire_idx, seg_idx]
	var bm := BoxMesh.new()
	bm.size = Vector3(0.025, 0.025, length)
	seg.mesh = bm
	# Orient local +Z to point from a to b.
	var fwd : Vector3 = delta / length
	# Pick a stable up vector: if the wire is near-vertical, fall back to +X.
	var up_ref : Vector3 = Vector3.UP
	if absf(fwd.dot(up_ref)) > 0.99:
		up_ref = Vector3.RIGHT
	var right : Vector3 = up_ref.cross(fwd).normalized()
	var up : Vector3 = fwd.cross(right).normalized()
	var basis := Basis(right, up, fwd)
	var centre : Vector3 = (a + b) * 0.5
	seg.transform = Transform3D(basis, centre)
	seg.material_override = _wire_mat
	add_child(seg)
