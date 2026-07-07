extends Node3D
## Geometry probe for the passenger cars (#car-fix). Loads each car scene, lets it
## run load_model() (correction yaw/pitch + auto-ruler), then MEASURES the result
## so orientation/scale bugs are provable instead of eyeballed:
##   • final union AABB (X/Y/Z) → which axis is the LENGTH, and is it flat?
##   • wheel node positions → are all 4 near the bottom (four wheels down)?
##   • front/back-named meshes → can we tell which end is the windshield?
##
## Canonical CeDo forward = local -Z, so a correctly-placed car should have:
##   length (max horizontal) along Z,  width along X,  height (Y) smallest,
##   4 wheels clustered near min-Y, and the windshield/front end toward -Z.
##
##   godot --headless --main-scene res://src/tests/probe_cars.tscn

# name, scene, real [L, W, H] metres (for proportion cross-check)
const CARS := [
	["AudiA3Sportback",   "res://src/scenes/vehicles/cars/AudiA3Sportback.tscn",   [4.31, 1.79, 1.43]],
	["BMWX1Placeholder",  "res://src/scenes/vehicles/cars/BMWX1Placeholder.tscn",  [4.45, 1.80, 1.54]],
	["FordKa2003",        "res://src/scenes/vehicles/cars/FordKa2003.tscn",        [3.62, 1.64, 1.37]],
	["FordStreetka",      "res://src/scenes/vehicles/cars/FordStreetka.tscn",      [3.62, 1.67, 1.31]],
	["HyundaiI20_2010",   "res://src/scenes/vehicles/cars/HyundaiI20_2010.tscn",   [3.94, 1.71, 1.49]],
	["SuzukiSwiftGLX",    "res://src/scenes/vehicles/cars/SuzukiSwiftGLX.tscn",    [3.85, 1.70, 1.51]],
	["VWGolfMk6",         "res://src/scenes/vehicles/cars/VWGolfMk6.tscn",         [4.20, 1.79, 1.48]],
	["VolvoV40Placeholder","res://src/scenes/vehicles/cars/VolvoV40Placeholder.tscn",[4.37, 1.80, 1.42]],
]
const FRONT_WORDS := ["headlight", "koplamp", "bonnet", "hood", "front", "voor", "windshield", "windscreen", "voorruit", "grille", "bumperf"]
const BACK_WORDS  := ["taillight", "achterlicht", "trunk", "boot", "rear", "achter", "tailgate", "backlight", "bumperr"]

func _ready() -> void:
	print("=== CAR GEOMETRY PROBE ===")
	for entry in CARS:
		await _probe(entry[0], entry[1], entry[2])
	print("=== done ===")
	get_tree().quit(0)

func _probe(nm: String, path: String, real: Array) -> void:
	var scn := load(path) as PackedScene
	if scn == null:
		print("\n[%s] FATAL: scene failed to load (%s)" % [nm, path]); return
	print("probing %s ..." % nm)
	var car : Node = scn.instantiate()
	get_tree().root.add_child(car)
	for i in range(8):
		await get_tree().process_frame

	# Union AABB over all mesh instances, in the car's LOCAL frame.
	var acc := {"aabb": AABB(), "any": false}
	_aabb_walk(car, (car as Node3D).global_transform.affine_inverse() if car is Node3D else Transform3D.IDENTITY, acc)
	if not acc["any"]:
		print("\n[%s] no meshes found (model not imported? proxy box only)" % nm)
		car.queue_free(); return
	var box : AABB = acc["aabb"]
	var sz : Vector3 = box.size
	var length_axis := "Z" if sz.z >= sz.x else "X"
	var length := maxf(sz.x, sz.z)
	var width  := minf(sz.x, sz.z)
	var height := sz.y

	# Wheels: nodes named "wheel" or VehicleWheel3D. Report their local Y spread.
	var wheels : Array = []
	_collect_wheels(car, wheels)
	var wy : Array = []
	for w in wheels:
		wy.append(snappedf((w as Node3D).position.y, 0.01))

	# Front/back polarity from named meshes.
	var front_z := _named_z(car, FRONT_WORDS)
	var back_z  := _named_z(car, BACK_WORDS)

	print("\n[%s]" % nm)
	print("  AABB size  L×W×H = %.2f × %.2f × %.2f m   (real ≈ %.2f × %.2f × %.2f)" % [
		length, width, height, real[0], real[1], real[2]])
	print("  length axis: %s   %s" % [length_axis, "(OK: length along Z)" if length_axis == "Z" else "(!! sideways — 90° yaw off)"])
	print("  flat check: height=%.2f vs width=%.2f  %s" % [
		height, width, "(OK flat)" if height < width + 0.15 else "(!! too tall — tipped on nose/tail?)"])
	print("  center Y=%.2f  aabb min Y=%.2f  (0 ≈ wheels on origin plane)" % [box.position.y + sz.y * 0.5, box.position.y])
	print("  wheels found: %d   local Y: %s" % [wheels.size(), str(wy)])
	if front_z != null or back_z != null:
		print("  polarity: front-named z=%s  back-named z=%s  → %s" % [
			str(front_z), str(back_z), _polarity_verdict(front_z, back_z)])
	else:
		print("  polarity: no front/back-named meshes → cannot infer windshield end from geometry")
	car.queue_free()

func _polarity_verdict(fz, bz) -> String:
	if fz == null or bz == null:
		return "indeterminate"
	# Canonical forward = -Z, so the FRONT should be at more-negative Z than back.
	return "OK (front toward -Z)" if float(fz) < float(bz) else "!! BACKWARDS (front toward +Z — drives away from windshield)"

func _named_z(root: Node, words: Array):
	var best = null
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var nm := String(n.name).to_lower()
			for w in words:
				if nm.contains(w):
					var z : float = (n as Node3D).global_position.z
					if best == null:
						best = z
					return snappedf(z, 0.01)
	return best

func _collect_wheels(root: Node, out: Array) -> void:
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is VehicleWheel3D or (n is Node3D and String(n.name).to_lower().contains("wheel")):
			out.append(n)

func _aabb_walk(node: Node, xf: Transform3D, acc: Dictionary) -> void:
	var child_xf := xf
	if node is Node3D:
		child_xf = xf * (node as Node3D).transform
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var local : AABB = (node as MeshInstance3D).mesh.get_aabb()
		var world_box := child_xf * local
		if not acc["any"]:
			acc["any"] = true
			acc["aabb"] = world_box
		else:
			acc["aabb"] = (acc["aabb"] as AABB).merge(world_box)
	for c in node.get_children():
		_aabb_walk(c, child_xf, acc)
