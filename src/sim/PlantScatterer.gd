extends Node3D
class_name PlantScatterer

## Procedural Asset Scatterer for CeDo Simulator (ProtonScatter-style architecture).
## Deterministically scatters yard clutter: wooden Euro-pallets, plastic film flakes,
## and oil stains using high-performance MultiMeshInstance3D.

@export var seed_val : int = 1337
@export var flake_count : int = 180
@export var pallet_stack_count : int = 8

func _ready() -> void:
	call_deferred("_generate_scatter")

func _generate_scatter() -> void:
	_scatter_flakes()
	_scatter_pallets()

func _scatter_flakes() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val

	# MultiMesh for plastic film flakes
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.instance_count = flake_count

	# Low-poly thin plastic flake quad
	var qm := QuadMesh.new()
	qm.size = Vector2(0.12, 0.08)
	qm.orientation = PlaneMesh.FACE_Y
	mm.mesh = qm

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.6
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mmi := MultiMeshInstance3D.new()
	mmi.name = "ScatteredFlakes"
	mmi.multimesh = mm
	mmi.material_override = mat
	add_child(mmi)

	var colors := [
		Color(0.92, 0.25, 0.20), # red film
		Color(0.20, 0.55, 0.90), # blue film
		Color(0.95, 0.90, 0.25), # yellow film
		Color(0.90, 0.92, 0.95), # clear/white film
		Color(0.25, 0.75, 0.35)  # green film
	]

	# Scatter near conveyors, shredders, and bale loading bays
	var origins := [
		Vector3(0.0, 0.02, 12.0),
		Vector3(-8.0, 0.02, 22.0),
		Vector3(14.0, 0.02, -18.0),
		Vector3(-18.0, 0.02, 5.0)
	]

	for i in flake_count:
		var orig : Vector3 = origins[rng.randi() % origins.size()]
		var px : float = orig.x + rng.randf_range(-4.5, 4.5)
		var pz : float = orig.z + rng.randf_range(-4.5, 4.5)
		var py : float = orig.y + rng.randf_range(0.001, 0.005) # slight vertical offset to avoid z-fighting
		var rot_y : float = rng.randf_range(0.0, TAU)
		var scale_f : float = rng.randf_range(0.6, 1.4)

		var t := Transform3D(Basis(Vector3.UP, rot_y).scaled(Vector3.ONE * scale_f), Vector3(px, py, pz))
		mm.set_instance_transform(i, t)
		mm.set_instance_color(i, colors[rng.randi() % colors.size()])

func _scatter_pallets() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 99

	# Euro pallet locations along yard fences / outdoor walls
	var yard_spots := [
		Vector3(-32.0, 0.0, 42.0),
		Vector3(-28.0, 0.0, 48.0),
		Vector3(25.0, 0.0, 52.0),
		Vector3(30.0, 0.0, 46.0),
		Vector3(-35.0, 0.0, -25.0)
	]

	var pallet_wood_mat := StandardMaterial3D.new()
	pallet_wood_mat.albedo_color = Color(0.68, 0.54, 0.38) # pine wood
	pallet_wood_mat.roughness = 0.85

	var pallet_root := Node3D.new()
	pallet_root.name = "PalletStacks"
	add_child(pallet_root)

	for spot in yard_spots:
		var stack_h : int = rng.randi_range(2, 5)
		var stack_yaw : float = rng.randf_range(-0.15, 0.15)
		for h in stack_h:
			var p := _create_pallet_mesh(pallet_wood_mat)
			p.position = spot + Vector3(0.0, float(h) * 0.144, 0.0)
			p.rotation.y = stack_yaw + rng.randf_range(-0.03, 0.03)
			pallet_root.add_child(p)

func _create_pallet_mesh(mat: Material) -> Node3D:
	var p := Node3D.new()
	# Standard Euro-pallet (1.20m x 0.80m x 0.144m)
	# Top deck boards
	for bx in 5:
		var board := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.20, 0.022, 0.14)
		board.mesh = bm
		board.material_override = mat
		board.position = Vector3(0.0, 0.133, -0.33 + float(bx) * 0.165)
		p.add_child(board)

	# 3 stringer runners & 9 blocks
	for sz in [-0.33, 0.0, 0.33]:
		for sx in [-0.50, 0.0, 0.50]:
			var blk := MeshInstance3D.new()
			var blkm := BoxMesh.new()
			blkm.size = Vector3(0.14, 0.078, 0.14)
			blk.mesh = blkm
			blk.material_override = mat
			blk.position = Vector3(sx, 0.061, sz)
			p.add_child(blk)

	return p
