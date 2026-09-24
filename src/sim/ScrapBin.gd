extends StaticBody3D
class_name ScrapBin
## Rulings §20 (2026-09-24): "A scrap bin near the belt" — the container by
## line 1's first conveyor that the scrap picked off a bale goes into.
## Catalog placeable `scrap_bin` (Logistics; placed in LINE_1_SEQ beside
## opzetband 1). MetalScrap drops into the nearest one within its DUMP_RANGE
## (add_scrap); the pieces are counted, their kg summed, and a heap of dark
## lumps grows in the bin so the shift's catch is visible. Not a flow node
## (MachineFlow role none): metal leaves the film stream here for good.

var scrap_kg : float = 0.0
var pieces : Array[String] = []
var _heap : Node3D = null

func _ready() -> void:
	add_to_group("scrap_bin")
	if not has_meta("placeable_id"):
		set_meta("placeable_id", "scrap_bin")

## Take a piece. Returns the kg accepted (all of it — a scrap bin does not
## fill up on this shift's scale).
func add_scrap(kg: float, kind: String = "scrap") -> float:
	if kg <= 0.0:
		return 0.0
	scrap_kg += kg
	pieces.append(kind)
	_grow_heap(kind)
	return kg

func piece_count() -> int:
	return pieces.size()

func crosshair_prompt(_player: Node3D) -> String:
	if pieces.is_empty():
		return "Scrap bin — empty"
	return "Scrap bin — %d piece(s), %.0f kg" % [pieces.size(), scrap_kg]

func crosshair_interact(_player: Node3D) -> void:
	pass

## One dark lump per piece, stacked pseudo-randomly inside the bin's walls.
func _grow_heap(kind: String) -> void:
	if _heap == null:
		_heap = Node3D.new()
		_heap.name = "ScrapHeap"
		_heap.set_meta("no_merge", true)
		add_child(_heap)
	var n : int = pieces.size()
	var mi := MeshInstance3D.new()
	var size_m : float = 0.30 if kind == "anvil" or kind == "plough_part" else 0.22
	if kind == "wheel":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.2
		cm.bottom_radius = 0.2
		cm.height = 0.14
		mi.mesh = cm
		mi.rotation = Vector3(0.0, 0.0, PI * 0.5)
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(size_m, size_m * 0.6, size_m * 0.8)
		mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.36, 0.28, 0.20) if kind != "wheel" else Color(0.10, 0.10, 0.11)
	m.roughness = 0.85
	m.metallic = 0.3
	mi.material_override = m
	var rng := RandomNumberGenerator.new()
	rng.seed = n * 7919
	mi.position = Vector3(rng.randf_range(-0.22, 0.22), 0.30 + 0.09 * float(n), rng.randf_range(-0.22, 0.22))
	mi.rotation.y = rng.randf_range(0.0, TAU)
	_heap.add_child(mi)
