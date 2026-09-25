extends Node3D
## Regression test for the 377-km spawn bug: a MIXED world_layout.json
## (player_spawn re-saved in Dutch RD coords ~1e5 m, while vehicles / yards /
## line_starts are already scene-absolute) must load with EVERY marker in ONE
## frame — the per-marker conversion shifts only RD-scale values.
##
## FRAME (2026-07-21): the RD shift is the building TILE centre, the same value
## MainWorld.tscn's BuildingShell transform uses, so converted markers land
## SCENE-ABSOLUTE. It is no longer taken from player_spawn — that produced
## player-relative offsets (player_spawn == 0), a frame no reader uses, and cost
## 228 m of vehicle misplacement. Expected values below are derived from the
## mesh centre, not copied from WorldLayout's own arithmetic.
##
## The three fixtures are written to a SCRATCH file, and each fresh WorldLayout
## instance reads them through layout_path_override. The operator's
## user://world_layout.json is never opened for writing, only compared at the
## end (src/tests/world_layout_guard.gd). Until 2026-09-25 each fixture went
## OVER his file with a truncating FileAccess.WRITE, and his bytes were written
## back at the end, so a kill mid-run left one of the fixtures as his world.
##   godot --headless --main-scene res://src/tests/test_world_layout_coords.tscn

const TILE_OBJ := "res://assets/models/CeDo_building.obj"
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new("__wlcoords__")

## Independent derivation of the RD→scene shift: read the tile mesh directly
## instead of asking WorldLayout what it used.
func _tile_shift() -> Vector2:
	var mesh = ResourceLoader.load(TILE_OBJ)
	if mesh is Mesh:
		var c : Vector3 = (mesh as Mesh).get_aabb().get_center()
		return Vector2(c.x, c.z)
	return Vector2.ZERO

var _pass := 0
var _fail := 0


func _ok(c: bool, m: String) -> void:
	if c: _pass += 1
	else: _fail += 1
	print(("  ok    : " if c else "  FAIL  : ") + m)


func _ready() -> void:
	print("=== world_layout coordinate conversion (377 km bug) ===")
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

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
	var shift := _tile_shift()
	_ok(shift != Vector2.ZERO, "tile mesh readable — RD shift derived independently %s" % str(shift))
	var wl = load("res://src/autoload/WorldLayout.gd").new()
	wl.layout_path_override = _wlg.scratch
	wl._load()
	# The RD player_spawn must land where the tile anchor puts it — NOT at zero.
	# A zero here means the loader re-centred on the marker itself, which is the
	# player-relative frame the engine's readers do not use.
	var want_ps := Vector2(183857.125 - shift.x, -329241.46875 - shift.y)
	_ok(Vector2(wl.player_spawn.x, wl.player_spawn.z).distance_to(want_ps) < 0.01,
		"MIXED: RD player_spawn converted to scene-absolute %s (want %s), NOT re-centred to zero"
			% [str(Vector2(wl.player_spawn.x, wl.player_spawn.z)), str(want_ps)])
	_ok(Vector2(wl.player_spawn.x, wl.player_spawn.z).length() > 1.0,
		"MIXED: player_spawn is NOT zero — the plant anchor keeps its own scene position")
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
	wl2.layout_path_override = _wlg.scratch
	wl2._load()
	var fk2 : Vector3 = wl2.vehicle_spawns["forklift"][0]
	var want_fk2 := Vector2(183900.0 - shift.x, -329200.0 - shift.y)
	_ok(Vector2(fk2.x, fk2.z).distance_to(want_fk2) < 0.01,
		"ALL-RD: vehicle converted to scene-absolute %s (want %s)" % [str(Vector2(fk2.x, fk2.z)), str(want_fk2)])
	# The RELATIVE geometry the operator drew must survive the conversion — the
	# forklift was authored 43 m east / 41 m north of the spawn in RD.
	var sep := Vector2(fk2.x - wl2.player_spawn.x, fk2.z - wl2.player_spawn.z)
	_ok(absf(sep.x - 43.0) < 0.01 and absf(sep.y - 41.0) < 0.01,
		"ALL-RD: forklift-to-spawn separation preserved (%.1f, %.1f)" % [sep.x, sep.y])
	_ok(Vector2(wl2.player_spawn.x, wl2.player_spawn.z).length() > 1.0,
		"ALL-RD: player_spawn keeps a real scene position (not zeroed)")
	wl2.free()

	# ── Case 3: ALL-LOCAL file (already converted) — load is a no-op ───────────
	_write_layout({
		"player_spawn":   {"x": 0.0, "y": 0.0, "z": 0.0},
		"vehicle_spawns": {"forklift": [{"x": 42.6, "y": 0.0, "z": -43.3}]},
	})
	var wl3 = load("res://src/autoload/WorldLayout.gd").new()
	wl3.layout_path_override = _wlg.scratch
	wl3._load()
	var fk3 : Vector3 = wl3.vehicle_spawns["forklift"][0]
	_ok(absf(fk3.x - 42.6) < 0.01 and absf(fk3.z + 43.3) < 0.01,
		"ALL-LOCAL: markers untouched on load")
	wl3.free()

	var c : Array = _wlg.real_layout_check()
	_ok(c[0], c[1])
	_wlg.disarm()
	print("\nResult: %d ok, %d fail" % [_pass, _fail])
	get_tree().quit(0 if _fail == 0 else 1)


func _write_layout(d: Dictionary) -> void:
	var f := FileAccess.open(_wlg.scratch, FileAccess.WRITE)
	f.store_string(JSON.stringify(d, "\t"))
	f.close()

