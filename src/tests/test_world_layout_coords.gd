extends Node3D
## Regression test for the 377-km spawn bug: a MIXED world_layout.json
## (player_spawn re-saved in Dutch RD coords ~1e5 m, while vehicles / yards /
## line_starts are already small local offsets) must load with EVERY marker as
## a sane local offset — the per-marker conversion shifts only RD-scale values.
##
## Backs up + restores the real user://world_layout.json.
##   godot --headless --main-scene res://src/tests/test_world_layout_coords.tscn

const PATH := "user://world_layout.json"

var _pass := 0
var _fail := 0
var _backup = null


func _ok(c: bool, m: String) -> void:
	if c: _pass += 1
	else: _fail += 1
	print(("  ok    : " if c else "  FAIL  : ") + m)


func _ready() -> void:
	print("=== world_layout coordinate conversion (377 km bug) ===")
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		_backup = f.get_as_text()
		f.close()

	# ── Case 1: MIXED file (the user's actual corruption shape) ────────────────
	_write_layout({
		"player_spawn":   {"x": 183857.125, "y": 0.0, "z": -329241.46875},
		"factory_center": {"x": 183857.125, "y": 0.0, "z": -329241.46875},
		"vehicle_spawns": {"forklift": [{"x": 42.6, "y": 0.0, "z": -43.3}]},
		"line_starts":    {"3c": {"x": 98.5, "y": 0.0, "z": -62.0}},
		"bale_yards":     [{"supplier_id": "rotterdam", "corners": [
			{"x": 26.2, "y": 0.0, "z": 126.1}, {"x": 40.0, "y": 0.0, "z": 126.1},
			{"x": 40.0, "y": 0.0, "z": 140.0}, {"x": 26.2, "y": 0.0, "z": 140.0}]}],
		"satellite": {"center_rd_x": 184112.5, "center_rd_y": 329382.25,
			"extent_m": 400.0, "has_image": true},
	})
	var wl = load("res://src/autoload/WorldLayout.gd").new()
	wl._load()
	_ok(wl.player_spawn.length() < 1.0,
		"MIXED: RD player_spawn localized to ~zero (got %s)" % str(wl.player_spawn))
	var fk : Vector3 = wl.vehicle_spawns["forklift"][0]
	_ok(Vector2(fk.x, fk.z).length() < 100.0,
		"MIXED: local forklift offset UNTOUCHED (got %.1f, %.1f — was −183814 before fix)" % [fk.x, fk.z])
	_ok(absf(fk.x - 42.6) < 0.01 and absf(fk.z + 43.3) < 0.01,
		"MIXED: forklift offset exactly preserved")
	var ls : Vector3 = wl.line_starts["3c"]
	_ok(Vector2(ls.x, ls.z).length() < 200.0, "MIXED: line_start 3c stays local")
	var c0 : Vector3 = wl.bale_yards[0]["corners"][0]
	_ok(Vector2(c0.x, c0.z).length() < 200.0, "MIXED: yard corner stays local")
	wl.free()

	# ── Case 2: ALL-RD file (fresh WorldSetup save) still converts as before ───
	_write_layout({
		"player_spawn":   {"x": 183857.0, "y": 0.0, "z": -329241.0},
		"vehicle_spawns": {"forklift": [{"x": 183900.0, "y": 0.0, "z": -329200.0}]},
	})
	var wl2 = load("res://src/autoload/WorldLayout.gd").new()
	wl2._load()
	var fk2 : Vector3 = wl2.vehicle_spawns["forklift"][0]
	_ok(absf(fk2.x - 43.0) < 0.01 and absf(fk2.z - 41.0) < 0.01,
		"ALL-RD: vehicle converted to local offset (got %.1f, %.1f)" % [fk2.x, fk2.z])
	_ok(wl2.player_spawn.length() < 1.0, "ALL-RD: player_spawn localized to zero")
	wl2.free()

	# ── Case 3: ALL-LOCAL file (already converted) — load is a no-op ───────────
	_write_layout({
		"player_spawn":   {"x": 0.0, "y": 0.0, "z": 0.0},
		"vehicle_spawns": {"forklift": [{"x": 42.6, "y": 0.0, "z": -43.3}]},
	})
	var wl3 = load("res://src/autoload/WorldLayout.gd").new()
	wl3._load()
	var fk3 : Vector3 = wl3.vehicle_spawns["forklift"][0]
	_ok(absf(fk3.x - 42.6) < 0.01 and absf(fk3.z + 43.3) < 0.01,
		"ALL-LOCAL: markers untouched on load")
	wl3.free()

	_restore()
	print("\nResult: %d ok, %d fail" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _write_layout(d: Dictionary) -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()


func _restore() -> void:
	if _backup is String:
		var f := FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(_backup)
		f.close()
	elif FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	print("  (restored original world_layout.json)")
