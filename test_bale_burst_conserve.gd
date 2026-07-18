extends SceneTree
## Proof BaleBurst conserves mass even when some length-chunks are EMPTY
## (bughunt 2026-07-17). The bale's sheet meshes are clustered at one end so
## only a couple of the 6 X-bins get any mesh; the surviving pieces must still
## add up to the intact bale's mass (previously each empty bin's src_mass/CHUNKS
## share was silently destroyed).
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_bale_burst_conserve.gd

var _ran := false

func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	var root := get_root()

	# Intact bale: 6 m long, mass 600 kg, with a Sheets node of real meshes all
	# clustered in the first ~third so bins 2..5 come out empty.
	var bale := RigidBody3D.new()
	bale.mass = 600.0
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(6.0, 1.0, 1.0)   # half_x = 3.0
	cs.shape = bx
	bale.add_child(cs)
	root.add_child(bale)
	bale.global_position = Vector3.ZERO

	var sheets := Node3D.new()
	sheets.name = "Sheets"
	bale.add_child(sheets)
	# Cluster: x=-2.9,-2.7 → bin 0 ; x=-1.6 → bin 1. Bins 2..5 stay empty.
	for lx in [-2.9, -2.7, -1.6]:
		var mi := MeshInstance3D.new()
		mi.mesh = BoxMesh.new()
		sheets.add_child(mi)
		mi.position = Vector3(lx, 0.0, 0.0)

	var pieces : Array = BaleBurst.open(bale, root)
	var total := 0.0
	for p in pieces:
		total += (p as RigidBody3D).mass

	var fails := 0
	if pieces.size() > 0 and pieces.size() < 6:
		print("  OK  : %d live pieces (empty chunks correctly skipped)" % pieces.size())
	else:
		print("  FAIL: expected 1..5 live pieces, got %d" % pieces.size()); fails += 1
	if is_equal_approx(total, 600.0):
		print("  OK  : mass conserved — %d pieces sum to %.1f kg (bale was 600.0)" % [pieces.size(), total])
	else:
		print("  FAIL: mass NOT conserved — pieces sum %.1f kg, bale was 600.0 (%.1f lost)" % [total, 600.0 - total]); fails += 1

	print("=== BALE-BURST CONSERVATION TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
