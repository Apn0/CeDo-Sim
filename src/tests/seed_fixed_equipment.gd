extends Node3D
## Rough first-pass populate of documented FIXED (non-line) equipment (#populate).
##
## The plant docs give each installation an AREA, not a coordinate, so a precise
## auto-place is impossible. Per the operator's choice ("rough first-pass, then
## nudge") this lays the 56 catalog-backed items out as a GROUPED GRID inside the
## main hall, on the operating floor, then VERIFIES every one lands inside the
## true building footprint (same bf-rectangle test the regression harness uses)
## before emitting persistent factory entries. The operator then drags each to
## its real spot in K-mode.
##
## Reads : res://src/tests/fixed_equipment_ids.json  [{id, group, name}, ...]
## Writes: user://fixed_equipment_entries.json       [{id,x,y,z,rot_y,h}, ...]
##
##   godot --headless --main-scene res://src/tests/seed_fixed_equipment.tscn
##
## Reuses the operator-verified bf→PC affine + interior rectangles from
## regression_world_save.gd (single source of truth for "inside the building").

const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
const BF_RECTS := [
	[0.0, 120.0, 0.0, 61.0], [120.0, 150.7, 0.0, 31.5], [120.0, 131.5, 31.5, 61.0],
	[57.0, 81.0, 61.0, 66.0], [81.0, 131.5, 61.0, 71.5],
]
const INSIDE_MARGIN := 0.6
const IDS_PATH   := "res://src/tests/fixed_equipment_ids.json"
const OUT_PATH   := "user://fixed_equipment_entries.json"
const TEST_SLOT  := "new_building_test"

# One z-band (metres up the hall) per system; items march along +x within a band.
const Z_BAND := {
	"water": 8.0, "air": 15.0, "silo": 22.0, "control": 30.0,
	"utility": 42.0, "structure": 50.0, "other": 55.0,
}
const GROUP_ORDER := ["water", "air", "silo", "control", "utility", "structure", "other"]
const X_START := 10.0
const X_STEP  := 6.0

func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU
func _pc_to_bf(pc: Vector2) -> Vector2:
	var d := pc - BF_O
	return Vector2(d.dot(BF_XU), d.dot(BF_ZU))
func _bf_inside(bf: Vector2, margin: float) -> bool:
	for r in BF_RECTS:
		if bf.x >= r[0] - margin and bf.x <= r[1] + margin \
				and bf.y >= r[2] - margin and bf.y <= r[3] + margin:
			return true
	return false

func _ready() -> void:
	print("=== SEED FIXED EQUIPMENT (rough first-pass) ===")
	var items := _load_ids()
	if items.is_empty():
		print("FATAL: no ids loaded from %s" % IDS_PATH); get_tree().quit(2); return

	# Boot the real MainWorld (load-existing so it builds the configured world).
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(80):
		await get_tree().process_frame

	if not Plant.is_initialized():
		print("FATAL: Plant not initialized after boot"); get_tree().quit(2); return
	if not Plant.has_method("pc_to_scene"):
		print("FATAL: Plant.pc_to_scene missing"); get_tree().quit(2); return
	var floor_y : float = Plant.floor_top_y()
	print("floor_top_y = %.2f" % floor_y)

	# Lay out grouped grid, place, verify inside footprint.
	var entries : Array = []
	var placed := 0
	var inside := 0
	var bad_ids : Array = []
	for g in GROUP_ORDER:
		var z : float = Z_BAND[g]
		var col := 0
		for it in items:
			if String(it.get("group", "")) != g:
				continue
			var bf := Vector2(X_START + float(col) * X_STEP, z)
			col += 1
			var pc := _bf_to_pc(bf)
			var pos : Vector3 = Plant.pc_to_scene(pc)
			pos.y = floor_y
			var id := String(it.get("id", ""))
			# Build to confirm the id is real; verify containment; then free.
			var node = PlaceableCatalog.build_node(id, false)
			if node == null:
				bad_ids.append(id); continue
			placed += 1
			node.free()
			var bf_back := _pc_to_bf(Plant.scene_to_pc(pos))
			var is_in := _bf_inside(bf_back, INSIDE_MARGIN)
			if is_in:
				inside += 1
			else:
				print("  OUTSIDE: %-24s bf=(%.1f, %.1f)" % [id, bf_back.x, bf_back.y])
			entries.append({
				"id": id, "x": pos.x, "y": pos.y, "z": pos.z, "rot_y": 0.0, "h": 0.0,
			})

	print("placements: %d built, %d/%d inside footprint, %d bad id(s) %s" % [
		placed, inside, entries.size(), bad_ids.size(), str(bad_ids)])

	# Emit the factory entries (a plain list to merge into a per-save _factory.json).
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(entries, "\t"))
		f.close()
		print("wrote %d entries → %s" % [entries.size(), ProjectSettings.globalize_path(OUT_PATH)])

	var ok := (bad_ids.is_empty() and inside == entries.size() and entries.size() == items.size())
	print("Result: %s (%d/%d inside, %d built)" % [
		"PASS" if ok else "FAIL", inside, entries.size(), placed])
	world.queue_free()
	get_tree().quit(0 if ok else 1)

func _load_ids() -> Array:
	if not FileAccess.file_exists(IDS_PATH):
		return []
	var raw := FileAccess.get_file_as_string(IDS_PATH)
	var parsed = JSON.parse_string(raw)
	return parsed if parsed is Array else []
