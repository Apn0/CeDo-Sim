extends Node3D
class_name StaffParking

## CeDo staff parking lot (#134 / #135). Procedural mesh: asphalt slab, painted
## white bay-line stripes between two rows facing each other across an aisle,
## raised curb edges, concrete entrance pad. Sized + positioned to match the
## operator's Google Maps satellite of De Asselen Kuil, but tunable from
## WorldLayout when the operator wires the WorldSetup tool.
##
## Slot layout the satellite shows: two parallel rows of about 8-10 angled
## bays each, facing each other across a 6-m aisle. Operator's car spotted in
## right row slot 2 (Swift); Abdellilah's Ka in left row slot 1; Audi (Emrah)
## adjacent; i20 (Roman) further down; black Pascal & Vincent across.
##
## Slot indexing (0-based from north end):
##   left row  → slot_left[0..N-1]   bay normal points +X (cars face east)
##   right row → slot_right[0..N-1]  bay normal points -X (cars face west)
## bay_world_transform(side, idx) returns the Transform3D for parking a Car at
## that slot (rotation faces the aisle, position at bay centre at floor y).

# ── Configuration (operator-tunable via WorldLayout later) ────────────────────
@export var bay_length     : float = 5.0     # depth of a single bay along Z
@export var bay_width      : float = 2.6     # width of a single bay along X
@export var aisle_width    : float = 6.0     # gap between left + right rows
@export var bay_count      : int   = 10      # bays per row
@export var line_paint_w   : float = 0.12    # painted line stripe width
@export var line_paint_y   : float = 0.012   # how far above asphalt the paint sits (avoid z-fighting)
@export var curb_height    : float = 0.15
@export var curb_width     : float = 0.20
@export var surface_y      : float = 0.0     # asphalt top sits at this Y

# Computed at build time.
var _slot_left_xfs  : Array = []
var _slot_right_xfs : Array = []

func _ready() -> void:
	_build_asphalt()
	_build_bay_lines()
	_build_curbs()
	_build_parking_sign()
	_compute_slot_transforms()

# Total footprint dims (X width, Z length).
func footprint() -> Vector2:
	var x : float = 2.0 * bay_length + aisle_width
	var z : float = float(bay_count) * bay_width
	return Vector2(x, z)

# ── Asphalt slab ──────────────────────────────────────────────────────────────
func _build_asphalt() -> void:
	var fp := footprint()
	var asphalt := MeshInstance3D.new()
	asphalt.name = "Asphalt"
	var bm := BoxMesh.new()
	bm.size = Vector3(fp.x, 0.05, fp.y)
	asphalt.mesh = bm
	asphalt.position = Vector3(0.0, surface_y - 0.025, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.13, 0.13, 0.135)   # worn asphalt, almost black
	mat.roughness = 0.95
	mat.metallic = 0.0
	asphalt.material_override = mat
	add_child(asphalt)

# ── Bay-line stripes (white paint) ────────────────────────────────────────────
func _build_bay_lines() -> void:
	var paint := StandardMaterial3D.new()
	paint.albedo_color = Color(0.95, 0.95, 0.92)
	paint.roughness = 0.6
	paint.metallic = 0.0
	# Each row gets (bay_count + 1) divider lines running ALONG +Z, at the bay
	# borders. Length = bay_length (the depth of the bay, into the row).
	for side in [-1, 1]:
		var row_x_centre : float = float(side) * (aisle_width * 0.5 + bay_length * 0.5)
		for i in (bay_count + 1):
			var z : float = -footprint().y * 0.5 + float(i) * bay_width
			var stripe := MeshInstance3D.new()
			stripe.name = "BayLine_%d_%s" % [i, "L" if side == -1 else "R"]
			var bm := BoxMesh.new()
			bm.size = Vector3(bay_length - 0.02, 0.005, line_paint_w)
			stripe.mesh = bm
			stripe.position = Vector3(row_x_centre, surface_y + line_paint_y, z)
			stripe.material_override = paint
			add_child(stripe)
	# Inner edge "head" line — runs all the way along the row's inner edge so
	# operator can see where the bay STOPS at the aisle.
	for side in [-1, 1]:
		var inner_x : float = float(side) * (aisle_width * 0.5)
		var head := MeshInstance3D.new()
		head.name = "HeadLine_%s" % ("L" if side == -1 else "R")
		var bm := BoxMesh.new()
		bm.size = Vector3(line_paint_w, 0.005, footprint().y - 0.02)
		head.mesh = bm
		head.position = Vector3(inner_x, surface_y + line_paint_y, 0.0)
		head.material_override = paint
		add_child(head)

# ── Concrete curb runs around the OUTSIDE perimeter (not aisle side) ──────────
func _build_curbs() -> void:
	var fp := footprint()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.60, 0.58)   # weathered concrete
	mat.roughness = 0.85
	# Two long curbs along ±X (the outer faces of each row).
	for side in [-1, 1]:
		var x : float = float(side) * (fp.x * 0.5 + curb_width * 0.5)
		var curb := MeshInstance3D.new()
		curb.name = "Curb_%s" % ("W" if side == -1 else "E")
		var bm := BoxMesh.new()
		bm.size = Vector3(curb_width, curb_height, fp.y + curb_width * 2.0)
		curb.mesh = bm
		curb.position = Vector3(x, surface_y + curb_height * 0.5, 0.0)
		curb.material_override = mat
		add_child(curb)
	# Two short curbs along ±Z (the north/south ends).
	for side in [-1, 1]:
		var z : float = float(side) * (fp.y * 0.5 + curb_width * 0.5)
		var curb := MeshInstance3D.new()
		curb.name = "Curb_%s" % ("S" if side == -1 else "N")
		var bm := BoxMesh.new()
		bm.size = Vector3(fp.x + curb_width * 2.0, curb_height, curb_width)
		curb.mesh = bm
		curb.position = Vector3(0.0, surface_y + curb_height * 0.5, z)
		curb.material_override = mat
		add_child(curb)

# ── "P" parking sign post at the aisle entry (south edge) ─────────────────────
func _build_parking_sign() -> void:
	var fp := footprint()
	var post_h : float = 2.3
	var post := MeshInstance3D.new()
	post.name = "ParkingSignPost"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.04
	cm.bottom_radius = 0.04
	cm.height = post_h
	post.mesh = cm
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.78, 0.78, 0.80)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.4
	post.material_override = post_mat
	post.position = Vector3(-fp.x * 0.5 - 0.6, post_h * 0.5, -fp.y * 0.5 + 0.5)
	add_child(post)
	# Square blue P sign on top.
	var sign := MeshInstance3D.new()
	sign.name = "ParkingSign"
	var qm := QuadMesh.new()
	qm.size = Vector2(0.55, 0.55)
	sign.mesh = qm
	var sm := StandardMaterial3D.new()
	sm.albedo_color = Color(0.05, 0.32, 0.78)   # NL parking-sign blue
	sm.roughness = 0.6
	sign.material_override = sm
	sign.position = Vector3(-fp.x * 0.5 - 0.6, post_h - 0.20, -fp.y * 0.5 + 0.5 + 0.03)
	add_child(sign)
	# White P glyph — a thick PrismMesh stand-in (good enough at distance).
	var p := MeshInstance3D.new()
	p.name = "ParkingP"
	var pm := PrismMesh.new()
	pm.size = Vector3(0.28, 0.36, 0.012)
	p.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.95, 0.92)
	p.material_override = pmat
	p.position = Vector3(-fp.x * 0.5 - 0.6, post_h - 0.20, -fp.y * 0.5 + 0.5 + 0.05)
	add_child(p)

# ── Bay slot transforms ────────────────────────────────────────────────────────
func _compute_slot_transforms() -> void:
	_slot_left_xfs.clear()
	_slot_right_xfs.clear()
	var fp := footprint()
	for i in bay_count:
		var z : float = -fp.y * 0.5 + (float(i) + 0.5) * bay_width
		# Canonical CeDo direction (matches BaseVehicle._kinematic_move, which
		# uses `fwd := -global_transform.basis.z`, i.e. car-local -Z IS its
		# driving forward direction).
		#   LEFT row sits at world -X; aisle is at +X. Yaw -90° rotates
		#   car-local -Z onto world +X — nose points OUT into the aisle, rear
		#   against the curb. Driver can pull straight out of the bay forward.
		#   RIGHT row sits at world +X; aisle is at -X. Yaw +90° rotates
		#   car-local -Z onto world -X — nose points OUT into the aisle,
		#   mirror of left.
		var left_xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(-90.0)),
			Vector3(-aisle_width * 0.5 - bay_length * 0.5, surface_y, z))
		_slot_left_xfs.append(left_xf)
		var right_xf := Transform3D(
			Basis(Vector3.UP, deg_to_rad(90.0)),
			Vector3( aisle_width * 0.5 + bay_length * 0.5, surface_y, z))
		_slot_right_xfs.append(right_xf)

## Returns the world Transform3D for parking a car at the given slot.
## `side` = -1 for left row, +1 for right row. `idx` = 0..bay_count-1 from south end.
func bay_world_transform(side: int, idx: int) -> Transform3D:
	idx = clampi(idx, 0, bay_count - 1)
	var local : Transform3D = _slot_left_xfs[idx] if side == -1 else _slot_right_xfs[idx]
	return global_transform * local
