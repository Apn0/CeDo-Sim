extends Node3D
## Roundness proof for the hose-reel / air-hose-hook coils (#hose-detail).
##
## The coiled hose was a stack of TorusMesh rings with `rings = 6`, and in Godot
## `rings` is the slice count AROUND THE MAIN LOOP — 6 read as a literal hexagon.
## This measures the built geometry: every coil torus must now be round
## (rings >= 32) and every cylinder (drum/axle/valves) round (radial_segments
## >= 16). No renderer needed — we inspect the mesh resources directly.
##
##   godot --headless --path <proj> --main-scene res://src/tests/test_hose_reel_round.tscn

const Catalog = preload("res://src/build/PlaceableCatalog.gd")

var _fails : int = 0

func _check(cond: bool, msg: String) -> void:
	print(("  ok    : " if cond else "  FAIL  : ") + msg)
	if not cond:
		_fails += 1

func _ready() -> void:
	print("=== Hose reel / hook roundness proof ===")
	_test_reel("reel_water_thick_yellow", 0.045)
	_test_hook()
	print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

func _collect(node: Node, toruses: Array, cyls: Array) -> void:
	if node is MeshInstance3D:
		var m = (node as MeshInstance3D).mesh
		if m is TorusMesh:
			toruses.append(m)
		elif m is CylinderMesh:
			cyls.append(m)
	for c in node.get_children():
		_collect(c, toruses, cyls)

func _min_rings(toruses: Array) -> int:
	var lo := 100000
	for tm in toruses:
		lo = mini(lo, (tm as TorusMesh).rings)
	return lo

func _min_radial(cyls: Array) -> int:
	var lo := 100000
	for cm in cyls:
		lo = mini(lo, (cm as CylinderMesh).radial_segments)
	return lo

func _test_reel(id: String, hose_r: float) -> void:
	print("[%s]" % id)
	var p := Node3D.new()
	add_child(p)
	# ghost=true builds the full visual but skips the HoseReel controller/Area.
	Catalog._m_hose_reel(p, Vector3(0.95, 1.10, 0.60), Color(0.96, 0.78, 0.16), true, hose_r)
	var toruses : Array = []
	var cyls : Array = []
	_collect(p, toruses, cyls)
	_check(toruses.size() >= 4, "coil built from >=4 rings (got %d)" % toruses.size())
	if toruses.size() > 0:
		var mr := _min_rings(toruses)
		_check(mr >= 32, "every coil torus is round — min rings=%d (was 6=hexagon)" % mr)
	if cyls.size() > 0:
		var mrad := _min_radial(cyls)
		_check(mrad >= 16, "every cylinder is round — min radial_segments=%d" % mrad)

func _test_hook() -> void:
	print("[hook_air_hose]")
	var p := Node3D.new()
	add_child(p)
	Catalog._m_air_hose_hook(p, Vector3(0.70, 1.00, 0.55), true)
	var toruses : Array = []
	var cyls : Array = []
	_collect(p, toruses, cyls)
	_check(toruses.size() >= 6, "air-hose coil built from >=6 rings (got %d)" % toruses.size())
	if toruses.size() > 0:
		var mr := _min_rings(toruses)
		_check(mr >= 32, "every air-coil torus is round — min rings=%d (was 6)" % mr)
