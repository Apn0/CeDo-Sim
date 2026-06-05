extends SceneTree
## Smoke test for the newly-added sorting-line machines (bunker, Shredder 1/2,
## inclined belt, feed hopper). Verifies:
##   - Each one is in the catalog (id + size + category)
##   - build_node() returns a working StaticBody3D in group "placed_object"
##   - MachineFlow.profile(id) returns a sensible role / port spec so LineFlow
##     auto-linking won't skip them

const _Catalog := preload("res://src/build/PlaceableCatalog.gd")
const _Flow    := preload("res://src/sim/MachineFlow.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Sorting line catalog smoke test")
	print("============================================================")
	_test_catalog_entries_present()
	_test_machineflow_profiles_present()
	_test_inclined_belt_climbs_8m()
	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

# =============================================================================
# Each new machine must be in the catalog with the right category
# =============================================================================
func _test_catalog_entries_present() -> void:
	print("[1] New sorting-line machines registered in catalog")
	var expected := {
		"bunker":            "Sorting",
		"shredder_1":        "Shredders",
		"shredder_2":        "Shredders",
		"inclined_belt_8m":  "Conveyance",
		"feed_hopper":       "Conveyance",
		# Line 3C extruder train + new separation machines (#144/#155/#156)
		"plasmaq":           "Extruders",
		"laser_filter":      "Extruders",
		"melt_pump":         "Extruders",
		"overband_magnet":   "Separation",
		"scraper_conveyor":  "Separation",
	}
	for id in expected:
		var item := _Catalog.get_item(id)
		_ok(not item.is_empty(), "catalog has '%s'" % id)
		if not item.is_empty():
			_ok(String(item["category"]) == expected[id],
				"'%s' category = '%s' (got '%s')" % [id, expected[id], item["category"]])
			# Build it (non-ghost) and check it's a StaticBody in the placed_object group
			var node = _Catalog.build_node(id, false)
			_ok(node != null, "'%s' build_node() returns a node" % id)
			if node != null:
				_ok(node is StaticBody3D, "'%s' built as StaticBody3D" % id)
				_ok(node.is_in_group("placed_object"),
					"'%s' in 'placed_object' group" % id)
				_ok(node.has_meta("placeable_id") and \
					String(node.get_meta("placeable_id")) == id,
					"'%s' carries placeable_id meta" % id)
				node.queue_free()

# =============================================================================
# MachineFlow gives each new machine a non-"none" role + ports
# =============================================================================
func _test_machineflow_profiles_present() -> void:
	print("[2] MachineFlow profiles assigned (so LineFlow links them)")
	var expected_roles := {
		"bunker":            "process",
		"shredder_1":        "process",
		"shredder_2":        "process",
		"inclined_belt_8m":  "conveyor",
		"feed_hopper":       "conveyor",
	}
	for id in expected_roles:
		var pr := _Flow.profile(id)
		_ok(String(pr["role"]) == expected_roles[id],
			"'%s' role = '%s' (got '%s')" % [id, expected_roles[id], pr["role"]])
		# in/out ports must be distinct so the connector has somewhere to go
		var p_in  : Vector3 = pr["in"]
		var p_out : Vector3 = pr["out"]
		_ok(p_in != p_out, "'%s' in != out (%s vs %s)" % [id, p_in, p_out])

# =============================================================================
# Inclined belt's bounding box matches an 8 m × 8 m diagonal (~45°)
# =============================================================================
func _test_inclined_belt_climbs_8m() -> void:
	print("[3] Inclined belt geometry: 8 m vertical rise + 8 m horizontal")
	var item := _Catalog.get_item("inclined_belt_8m")
	if item.is_empty():
		_ok(false, "inclined_belt_8m missing from catalog")
		return
	var sz: Vector3 = item["size"]
	_ok(sz.y >= 8.0, "bounding-box Y >= 8 m (=%.1f) — rises to feed-hopper height" % sz.y)
	_ok(sz.z >= 8.0, "bounding-box Z >= 8 m (=%.1f) — horizontal run matches rise" % sz.z)
	_ok(absf(sz.y - sz.z) < 0.6,
		"Y ≈ Z (45° incline within 0.6 m — actually %.2f, %.2f)" % [sz.y, sz.z])
