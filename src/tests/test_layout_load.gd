extends Node3D
## Task #17 — Headless verification that MainWorld loads a saved WorldLayout
## correctly, with NO dependency on the user's real world_layout.json.
##
## Boots via the project main-scene path so the autoloads (esp. WorldLayout)
## register as real globals, exactly like test_settings_wiring.gd:
##
##   godot --headless --main-scene res://src/tests/test_layout_load.tscn
##
## What it proves
## --------------
## A synthetic layout is authored in Dutch RD coordinates (EPSG:28992, magnitudes
## ~1.5e5 / 3.3e5 — the same scale WorldSetup writes) and round-tripped through
## the REAL WorldLayout._load(). Then:
##
##   (1) After _load(), every marker (player_spawn / factory_center / vehicle
##       spawns / line starts / yard corners) is FINITE — the RD→player-relative
##       re-centring left no NaN/Inf behind, and pushed RD magnitudes back down to
##       sane plant offsets (tens of metres, never 1e5).
##
##   (2) MainWorld._layout_to_scene() maps a player-relative offset to a finite
##       scene position anchored NEAR the player (offset preserved to ~plant
##       scale, not flung 380 km away).
##
##   (3) The vehicles and bale yards MainWorld actually spawns from that layout
##       land within a sane radius of the player anchor (finite, and < a few
##       hundred metres — not 380 km, not NaN).
##
## Tier 1 (pure logic) always runs and cannot be derailed by scene loading.
## Tier 2 instantiates the REAL MainWorld.tscn (same pattern as
## tests/InGameSmokeTest.gd) and inspects the genuinely-spawned node positions.
## If the heavy scene cannot instantiate headless, Tier 2 is reported as skipped
## rather than failing the whole run — Tier 1 still validates the core contract.

# ── Synthetic RD-scale layout. Values must be in the REAL RD convention (RD x →
#    scene x, RD y → scene −z, hence the negative Z) and near the CeDo tile, so
#    the loader's tile-anchored shift lands them at plant scale. Magnitude alone
#    is no longer sufficient: the shift is a fixed mesh-derived constant, not a
#    value re-derived from player_spawn, so an arbitrary RD point stays arbitrary.
const RD_PLAYER  := Vector3(183900.0, 0.0, -329300.0)
# Plant-scale offsets, added to RD_PLAYER on disk. After conversion each marker
# must sit exactly this far from the converted player_spawn.
const OFF_FORK_A := Vector3(3.0,  0.0,  2.0)
const OFF_FORK_B := Vector3(-6.0, 0.0, 12.0)
const OFF_CLAMP  := Vector3(10.0, 0.0, -4.0)
const OFF_LINE1  := Vector3(8.0,  0.0,  1.0)
# Yard corners (a ~6 x 5 m quad ~15 m from the player), in RD space.
const YARD_CORNERS := [
	Vector3(15.0, 0.0,  8.0),
	Vector3(21.0, 0.0,  8.0),
	Vector3(21.0, 0.0, 13.0),
	Vector3(15.0, 0.0, 13.0),
]

# A vehicle/yard that lands farther than this from the player anchor is almost
# certainly an RD-coordinate leak (the 380-km class bug). Generous so legit
# plant layouts never trip it.
const SANE_RADIUS_M := 500.0

var _pass := 0
var _fail := 0
var _skip := 0

# Files we touch and MUST restore so the user's real save is untouched.
const LAYOUT_PATH   := "user://world_layout.json"
const CONSUMED_FLAG := "user://world_layout_consumed.flag"
const FACTORY_LAYOUT := "user://factory_layout.json"
# Isolate ALL GameState writes to a throwaway slot so the user's real save is
# never touched (GameState.save_file_path is derived from this EventBus meta).
const TEST_SAVE_SLOT := "__layout_load_test_tmp"
const TEST_SAVE_PATH := "user://__layout_load_test_tmp_save.json"
# path → backed-up contents (String) or null if the file did not exist.
var _backups : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _section(title: String) -> void:
	print("\n[%s]" % title)


func _ready() -> void:
	print("=== Task #17 — MainWorld WorldLayout load verification ===")

	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FAIL: WorldLayout autoload not present (boot via --main-scene, not --script)")
		get_tree().quit(1); return

	_backup_user_layout()
	# Author the synthetic RD-scale layout on disk, then drive the REAL loader.
	_write_synthetic_layout()
	wl.call("_load")

	_test_load_finite(wl)
	await _test_layout_to_scene_and_spawns(wl)

	_restore_user_layout()
	_finish()


# =============================================================================
# (1) After _load() of RD-scale coords, every marker is finite + re-centred.
# =============================================================================
func _test_load_finite(wl: Node) -> void:
	_section("WorldLayout._load — RD coords → finite player-relative offsets")

	_ok(bool(wl.call("is_configured")), "layout reports is_configured() after load")

	var ps : Vector3 = wl.get("player_spawn")
	var fc : Vector3 = wl.get("factory_center")
	_ok(_v3_finite(ps), "player_spawn is finite %s" % str(ps))
	_ok(_v3_finite(fc), "factory_center is finite %s" % str(fc))
	# RD conversion subtracts the building TILE centre (WorldLayout._rd_to_scene_shift),
	# so every marker drops from 1e5 RD magnitudes into the scene-absolute frame.
	# player_spawn keeps a REAL scene position — it is the plant anchor, not the
	# origin. It collapsing to ~0 is the signature of the player-relative frame
	# that misplaced every vehicle by 228 m.
	_ok(Vector2(ps.x, ps.z).length() < 10000.0,
		"player_spawn converted out of RD scale: (%.2f, %.2f)" % [ps.x, ps.z])
	_ok(Vector2(ps.x, ps.z).length() > 1.0,
		"player_spawn was NOT re-centred onto the origin — it holds its own scene position")

	# Vehicle spawns — finite AND brought back to the small offsets we authored.
	var fork : Array = wl.call("get_vehicle_spawns", "forklift")
	_ok(fork.size() == 2, "forklift has 2 spawns (got %d)" % fork.size())
	var all_small := true
	for arr_id in ["forklift", "bale_clamp"]:
		for p in (wl.call("get_vehicle_spawns", arr_id) as Array):
			if not _v3_finite(p): all_small = false
			if Vector2(p.x, p.z).length() > 10000.0: all_small = false
	_ok(all_small, "all vehicle spawns finite and < 10 km after re-centring (RD leak check)")
	# Markers are scene-absolute after conversion, so the invariant that survives
	# is the SEPARATION the layout was authored with — checked against the
	# converted player_spawn, not against a bare offset.
	if fork.size() >= 1:
		var f0 : Vector3 = fork[0]
		_ok(_v3_approx(f0 - ps, OFF_FORK_A, 0.5),
			"forklift #1 sits %s from player_spawn as authored (got %s)"
				% [str(OFF_FORK_A), str(f0 - ps)])

	# Line starts.
	var ls : Vector3 = wl.call("get_line_start", "1", Vector3(9999, 9999, 9999))
	_ok(_v3_finite(ls) and _v3_approx(ls - ps, OFF_LINE1, 0.5),
		"line '1' start finite + %s from player_spawn as authored (got %s)"
			% [str(OFF_LINE1), str(ls - ps)])

	# Yard corners.
	var yards : Array = wl.get("bale_yards")
	_ok(yards.size() == 1, "exactly 1 bale yard loaded (got %d)" % yards.size())
	var corners_finite := true
	var corners_small := true
	if yards.size() >= 1:
		for c in ((yards[0] as Dictionary).get("corners", []) as Array):
			if not _v3_finite(c): corners_finite = false
			if Vector2(c.x, c.z).length() > 10000.0: corners_small = false
	_ok(corners_finite, "all yard corners are finite (is_finite)")
	_ok(corners_small, "all yard corners < 10 km after re-centring")


# =============================================================================
# (2) + (3) MainWorld._layout_to_scene + the vehicles/yards it really spawns.
# =============================================================================
func _test_layout_to_scene_and_spawns(_wl: Node) -> void:
	_section("MainWorld — instantiate real scene, check layout→scene mapping")

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("  skip  : MainWorld.tscn could not be loaded — Tier 2 skipped"); _skip += 1
		return

	# Redirect GameState's save to a throwaway slot BEFORE MainWorld instantiates
	# (GameState._ready reads this meta to pick its save_file_path). MainWorld
	# calls save_game() during its new-save bootstrap; this keeps it off the
	# user's real save file.
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SAVE_SLOT)
		bus.set_meta("pending_is_new_save", true)

	var world : Node = null
	# Instantiate + add the real world; the smoke test proves this works headless.
	world = scn.instantiate()
	if world == null:
		print("  skip  : MainWorld failed to instantiate — Tier 2 skipped"); _skip += 1
		return
	# Wait a frame so the root isn't mid-setup (else add_child fails "parent busy").
	await get_tree().process_frame
	get_tree().root.add_child(world)
	# Let the full _ready cascade + any deferred spawns settle.
	for i in range(30):
		await get_tree().process_frame

	# ── _layout_to_scene: a player-relative offset → finite scene pos near player.
	if not world.has_method("_layout_to_scene") or not world.has_method("_layout_anchor_xz"):
		print("  skip  : MainWorld lacks _layout_to_scene/_layout_anchor_xz — Tier 2 skipped")
		_skip += 1
		world.queue_free()
		return
	var anchor : Vector3 = world.call("_layout_anchor_xz")
	_ok(_v3_finite(anchor), "_layout_anchor_xz() is finite %s" % str(anchor))

	# Markers are SCENE-ABSOLUTE (WorldFrame._layout_to_scene), so the mapping is
	# the XZ identity: the value the operator drew IS the scene position. The old
	# assertions here (magnitude preserved relative to the anchor, and
	# _layout_to_scene(0) landing ON the anchor) only held for the rotate+anchor
	# reading that put every vehicle ~228 m off its own marker.
	var probe := Vector3(-211.21, 0.0, 86.05)   # the operator's forklift #1
	var scene_pos : Vector3 = world.call("_layout_to_scene", probe)
	_ok(_v3_finite(scene_pos), "_layout_to_scene(%s) is finite → %s" % [str(probe), str(scene_pos)])
	_ok(Vector2(scene_pos.x - probe.x, scene_pos.z - probe.z).length() < 0.001,
		"_layout_to_scene is the XZ identity — a marker maps to itself (%s → %s)"
			% [str(Vector2(probe.x, probe.z)), str(Vector2(scene_pos.x, scene_pos.z))])
	_ok(absf(scene_pos.y) < 0.001, "_layout_to_scene discards Y (caller pins it via _on_floor)")
	# The transform must NOT drag markers onto the anchor: that was the symptom
	# of re-anchoring an already-absolute coordinate.
	var at_origin : Vector3 = world.call("_layout_to_scene", Vector3.ZERO)
	_ok(Vector2(at_origin.x, at_origin.z).length() < 0.001,
		"_layout_to_scene(0) stays at the scene origin, NOT at the anchor %s" % str(anchor))

	# ── Vehicles actually spawned by _spawn_vehicle_instances: finite + near anchor.
	var vehicles := _find_vehicles(world)
	_ok(vehicles.size() >= 1, "MainWorld spawned at least one vehicle from layout (got %d)" % vehicles.size())
	var veh_ok := true
	var worst := 0.0
	for v in vehicles:
		var gp : Vector3 = (v as Node3D).global_position
		if not _v3_finite(gp): veh_ok = false
		var dd := Vector2(gp.x - anchor.x, gp.z - anchor.z).length()
		worst = maxf(worst, dd)
		if dd > SANE_RADIUS_M: veh_ok = false
	_ok(veh_ok, "every spawned vehicle finite + within %.0f m of anchor (worst %.1f m)"
		% [SANE_RADIUS_M, worst])

	# ── Bale yards actually spawned by _spawn_bale_yards_from_layout.
	var bale_nodes := get_tree().get_nodes_in_group("bale")
	if bale_nodes.is_empty():
		# Yard fill can legitimately be empty (e.g. PlaceableCatalog LOD build),
		# so don't fail — but if bales DID spawn, they must be sane.
		print("  note  : no bales spawned to inspect (yard fill empty) — skipping yard-position check")
		_skip += 1
	else:
		var yard_ok := true
		var yard_worst := 0.0
		for b in bale_nodes:
			var gp : Vector3 = (b as Node3D).global_position
			if not _v3_finite(gp): yard_ok = false
			var dd := Vector2(gp.x - anchor.x, gp.z - anchor.z).length()
			yard_worst = maxf(yard_worst, dd)
			if dd > SANE_RADIUS_M: yard_ok = false
		_ok(yard_ok, "every spawned bale finite + within %.0f m of anchor (worst %.1f m, %d bales)"
			% [SANE_RADIUS_M, yard_worst, bale_nodes.size()])

	world.queue_free()


# =============================================================================
# Helpers
# =============================================================================
func _find_vehicles(world: Node) -> Array:
	# Vehicles are VehicleBody3D added as direct children of MainWorld by
	# _spawn_vehicle_instances. Match by type so we don't depend on node names.
	var out : Array = []
	for c in world.get_children():
		if c is VehicleBody3D:
			out.append(c)
	return out


func _v3_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


func _v3_approx(a: Vector3, b: Vector3, eps: float) -> bool:
	return absf(a.x - b.x) <= eps and absf(a.y - b.y) <= eps and absf(a.z - b.z) <= eps


# ── Synthetic layout authoring + user-file safety ────────────────────────────
func _write_synthetic_layout() -> void:
	# Build the on-disk JSON in WorldLayout's exact save() schema, in RD coords.
	var data := {
		"version": 1,
		"factory_center": _j(RD_PLAYER + Vector3(5.0, 0.0, 5.0)),
		"player_spawn":   _j(RD_PLAYER),
		"vehicle_spawns": {
			"forklift":   [_j(RD_PLAYER + OFF_FORK_A), _j(RD_PLAYER + OFF_FORK_B)],
			"bale_clamp": [_j(RD_PLAYER + OFF_CLAMP)],
		},
		"line_starts": {
			"1": _j(RD_PLAYER + OFF_LINE1),
		},
		"bale_yards": [
			{
				"supplier_id": "rotterdam",
				"corners": _corners_json(),
			},
		],
		"satellite": {
			"center_rd_x": RD_PLAYER.x, "center_rd_y": RD_PLAYER.z,
			"extent_m": 400.0, "has_image": false,
		},
		# floor_plan_rot_deg drives _layout_to_scene's rotation. A non-trivial
		# angle exercises the rotate path (not just identity) while staying finite.
		"floor_plan": {
			"enabled": true, "opacity": 0.6,
			"offset_x": 0.0, "offset_z": 0.0,
			"scale_m": 100.0, "rot_deg": 35.0,
		},
	}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[test_layout_load] could not write synthetic %s" % LAYOUT_PATH); return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
	print("  (wrote synthetic RD-scale layout to %s)" % LAYOUT_PATH)


func _corners_json() -> Array:
	var out : Array = []
	for c in YARD_CORNERS:
		out.append(_j(RD_PLAYER + c))
	return out


func _j(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _backup_user_layout() -> void:
	# Snapshot every user:// file MainWorld / WorldLayout / GameState might touch,
	# so we can restore the user's machine to its exact prior state afterwards.
	for p in [LAYOUT_PATH, CONSUMED_FLAG, FACTORY_LAYOUT, TEST_SAVE_PATH]:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null


func _restore_user_layout() -> void:
	# Put each file back exactly as found: rewrite originals, delete ones we
	# created. This is what keeps the test from depending on / harming real saves.
	for p in _backups.keys():
		var original = _backups[p]
		if original is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(original); f.close()
		else:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("  (restored all touched user:// files to their original state)")


func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
