extends SceneTree
## Headless proof for the operator rule: cutting a bale's wires must SPLIT it
## using its OWN sheet meshes — not replace with other meshes, not disappear,
## mass conserved. Run:
##   Godot_v4.6.3_console --headless --path <proj> --script res://test_bale_split.gd

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true

func _run() -> void:
	var root := get_root()

	# ── Build a synthetic bale: RigidBody + BoxShape + a Sheets node of real,
	#    uniquely-materialled meshes (mirrors what _m_bale produces at runtime). ──
	var bale := RigidBody3D.new()
	bale.mass = 500.0
	bale.add_to_group("bale")
	bale.set_meta("material_origin", "rotterdam")
	var size := Vector3(1.2, 1.05, 1.05)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = size; col.shape = bx
	bale.add_child(col)
	var model := Node3D.new(); model.name = "Model"; bale.add_child(model)
	var sheets := Node3D.new(); sheets.name = "Sheets"; model.add_child(sheets)
	var N := 40
	var inner := size.x * 0.98
	var t := inner / float(N)
	var orig : Dictionary = {}   # mesh instance_id -> material instance_id
	for i in N:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(t * 0.95, size.y * 0.98, size.z * 0.98)
		mi.mesh = bm
		var m := StandardMaterial3D.new(); m.albedo_color = Color(float(i) / float(N), 0.5, 0.4)
		mi.material_override = m
		mi.name = "Sheet_%02d" % i
		mi.position = Vector3(-inner * 0.5 + t * (float(i) + 0.5), size.y * 0.5, 0.0)
		sheets.add_child(mi)
		orig[mi.get_instance_id()] = m.get_instance_id()
	root.add_child(bale)
	bale.global_position = Vector3.ZERO
	var before := orig.size()

	# ── ACT: the exact call WireCutter makes on the last wire ──
	var pieces : Array = BaleBurst.open(bale, root)

	# ── ASSERT ──
	var fails := 0
	if pieces.is_empty():
		print("FAIL: no pieces produced"); fails += 1

	var after : Dictionary = {}
	var total_mass := 0.0
	for p in pieces:
		total_mass += (p as RigidBody3D).mass
		for mi in _all_mesh(p):
			after[mi.get_instance_id()] = (mi.material_override.get_instance_id() if mi.material_override != null else 0)

	# (1) every original sheet mesh survives, as the SAME instance with the SAME
	#     material — proves "split", not "replace", and nothing vanished.
	var preserved := 0
	for iid in orig:
		if after.has(iid) and after[iid] == orig[iid]:
			preserved += 1
	if preserved == before:
		print("OK  : all %d real sheet meshes preserved (same instances + materials)" % before)
	else:
		print("FAIL: only %d/%d sheet meshes preserved (replaced or vanished)" % [preserved, before]); fails += 1

	# (2) nothing fabricated: no mesh exists that wasn't an original sheet.
	var fabricated := 0
	for iid in after:
		if not orig.has(iid):
			fabricated += 1
	if fabricated == 0:
		print("OK  : zero fabricated meshes — pieces are built from the bale's own film")
	else:
		print("FAIL: %d fabricated replacement meshes present" % fabricated); fails += 1

	# (3) count conserved: no meshes disappeared.
	if after.size() == before:
		print("OK  : no meshes vanished (%d in, %d out)" % [before, after.size()])
	else:
		print("FAIL: mesh count changed %d -> %d" % [before, after.size()]); fails += 1

	# (4) mass conserved across the pieces.
	if absf(total_mass - 500.0) <= 1.0:
		print("OK  : mass conserved %.1f kg across %d pieces" % [total_mass, pieces.size()])
	else:
		print("FAIL: mass not conserved %.1f kg (expected 500)" % total_mass); fails += 1

	# (5) pieces are real physics bodies (fall + collide), not scenery.
	var real_bodies := 0
	for p in pieces:
		if p is RigidBody3D and not (p as RigidBody3D).freeze:
			real_bodies += 1
	if real_bodies == pieces.size() and real_bodies > 0:
		print("OK  : %d live rigid pieces (fall + collide)" % real_bodies)
	else:
		print("FAIL: %d/%d pieces are live rigid bodies" % [real_bodies, pieces.size()]); fails += 1

	print("=== BALE SPLIT TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)

func _all_mesh(n: Node) -> Array:
	var out : Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_mesh(c))
	return out
