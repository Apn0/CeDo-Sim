extends Node3D
## LIGHT car-orientation probe (#car-fix). Loads ONLY the raw GLB/FBX model (no
## BaseVehicle physics/nav/audio — the full-car probe hung headless), applies the
## subclass correction (yaw + pitch), and measures the corrected orientation:
##   • L×W×H + which axis is the length (want Z = drive-forward)
##   • flat? (height smallest = four wheels down, not tipped)
##   • front/back-named meshes → windshield end
## For the shared traffic pack it also lists top-level node names (the individual
## cars) so we can see what the placeholders prune to.
##
##   godot --headless --main-scene res://src/tests/probe_cars_light.tscn

# name, model, yaw_deg, pitch_deg, is_pack
const MODELS := [
	["HyundaiI20-FIXED",  "res://assets/models/hyundai_i20_2010/hyundai_i20_2010.glb", 180.0, -90.0, false],
	["FordKa/Streetka", "res://assets/models/ford_ka_2003/ford_ka.glb", 180.0, -90.0, false],
	["AudiA3",      "res://assets/models/audi_a3_sportback/audi_a3_sportback.glb", 180.0, 0.0, false],
	["SuzukiSwift", "res://assets/models/suzuki_swift_glx/suzuki_swift_glx.fbx", 180.0, 0.0, false],
	["TrafficPack(Golf/BMW/Volvo)", "res://assets/models/traffic_cars_pack/ambulancesimulator_cars.glb", 180.0, 0.0, true],
]
const FRONT_WORDS := ["headlight", "koplamp", "bonnet", "hood", "front", "voor", "windshield", "windscreen", "voorruit", "grille"]
const BACK_WORDS  := ["taillight", "achterlicht", "trunk", "boot", "rear", "achter", "tailgate", "backlight"]

func _ready() -> void:
	print("=== LIGHT CAR ORIENTATION PROBE ===")
	for m in MODELS:
		await _probe(m[0], m[1], m[2], m[3], m[4])
	print("=== done ===")
	get_tree().quit(0)

func _probe(nm: String, path: String, yaw: float, pitch: float, is_pack: bool) -> void:
	print("\n[%s]  yaw=%.0f pitch=%.0f" % [nm, yaw, pitch])
	if not ResourceLoader.exists(path):
		print("  MISSING model: %s" % path); return
	var packed := load(path)
	if packed == null or not (packed is PackedScene):
		print("  could not load as PackedScene"); return
	var model : Node = (packed as PackedScene).instantiate()
	var wrap := Node3D.new()
	wrap.rotation = Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)
	wrap.add_child(model)
	add_child(wrap)
	await get_tree().process_frame

	var box := _mesh_aabb_global(wrap)
	if box.size == Vector3.ZERO:
		print("  no mesh geometry found"); wrap.queue_free(); return
	var sz := box.size
	var length := maxf(sz.x, sz.z)
	var width  := minf(sz.x, sz.z)
	var axis := "Z" if sz.z >= sz.x else "X"
	print("  corrected AABB  L×W×H = %.2f × %.2f × %.2f  (raw model units)" % [length, width, sz.y])
	print("  length axis: %s  %s" % [axis, "OK (length along Z = forward)" if axis == "Z" else "!! SIDEWAYS (length on X — needs ±90° yaw)"])
	print("  flat: height=%.2f width=%.2f  %s" % [sz.y, width, "OK (wheels down)" if sz.y < width + 0.20 else "!! TOO TALL (tipped — pitch wrong)"])
	var fz = _named_z(wrap, FRONT_WORDS)
	var bz = _named_z(wrap, BACK_WORDS)
	if fz != null and bz != null:
		print("  polarity: front z=%.2f back z=%.2f → %s" % [fz, bz,
			"OK (front toward -Z)" if fz < bz else "!! BACKWARDS (front toward +Z)"])
	else:
		print("  polarity: %s" % ["front-only" if fz != null else ("back-only" if bz != null else "no named front/back meshes → need a screenshot to confirm windshield end")])
	if is_pack:
		var names : Array = []
		for c in model.get_children():
			names.append(String(c.name))
		print("  pack top-level nodes (%d): %s" % [names.size(), str(names).substr(0, 400)])
	wrap.queue_free()

func _named_z(root: Node, words: Array):
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D:
			var low := String(n.name).to_lower()
			for w in words:
				if low.contains(w):
					return snappedf((n as Node3D).global_position.z, 0.01)
	return null

func _mesh_aabb_global(root: Node) -> AABB:
	var acc := AABB()
	var any := false
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.push_back(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var wb : AABB = (n as MeshInstance3D).global_transform * (n as MeshInstance3D).mesh.get_aabb()
			if not any:
				acc = wb; any = true
			else:
				acc = acc.merge(wb)
	return acc if any else AABB()
