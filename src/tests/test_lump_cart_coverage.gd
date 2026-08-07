extends Node3D
## LUMP CART COVERAGE — the operator ruling of 2026-08-03 made executable:
## "TWO lump carts per extruder — one at the VOOR side, one at the ACHTER side
## of the laser filter" (docs/plant/extruder_line_layout.md).
##
##   godot --headless --path <proj> res://src/tests/test_lump_cart_coverage.tscn
##
## Boots the REAL MainWorld (bench greens have lied here before — npc-05 was
## 31/31 while moving 0.00 kg), places ALL FOUR extruder line macros
## (line_1 / line_3a / line_3b / line_3c), and asserts for EVERY laser filter:
##
##   A. BINDING    LaserFilter's own runtime rebind (the 2 s catch-window scan,
##                 LaserFilter.gd:270-286) resolved BOTH nozzle carts — aisle
##                 (+X, voor) AND wall (-X, achter) — to two DISTINCT carts.
##                 This is the sim's real credit path, not a geometry re-check.
##   B. WINDOWS    each bound cart really is inside its nozzle's catch window
##                 (|dx| <= 0.55, |dz| <= 0.85 of eject_global()/_wall()) —
##                 printed with measured dx/dz so a drift shows numbers.
##   C. HEIGHTS    the asymmetric 07-15 ruling: one cart rides the 0.12 m
##                 bordes, the other stands on the ground. Measured: the bordes
##                 side is the one LaserFilter's lump_cart ("aisle") ref binds
##                 (the code's local labels are crossed vs plant vocabulary —
##                 see the note at check C).
##   D. BORDES     a lump_platform sits under the raised cart (XZ within 1.0 m).
##
## NON-VACUITY, stated up front: exactly 4 laser filters and exactly 8 lump
## carts must be found (one filter + 2 carts per line). 3C shipping with ZERO
## carts is precisely the defect this test exists to make impossible — it went
## unnoticed because nothing counted carts per filter.
##
## MUTATION-PROVEN (2026-08-03, see the commit): deleting the LINE_3C_SEQ
## furniture tail turns A red for the 3C filter and the cart count red — the
## green demonstrably depends on the thing it claims to prove.
##
## user:// SAFETY: same discipline as test_waslijn3c_overzicht — every touched
## file byte-backed-up + restored, operator allernieuwste_* saves hash-guarded.

const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)

const TEST_SLOT := "__lumpcov__"
const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__lumpcov___save.json", "user://__lumpcov___factory.json",
]

## All four extruder lines, spread the same 20 bf-units apart the waslijn3c
## test uses so nothing overlaps.
const LINES := {
	"line_1":  Vector2(4.0, 82.0),
	"line_3a": Vector2(4.0, 22.0),
	"line_3b": Vector2(4.0, 42.0),
	"line_3c": Vector2(4.0, 65.0),
}
const EXPECT_FILTERS := 4
const EXPECT_CARTS   := 8
const CATCH_DX := 0.55   # LaserFilter.CART_CATCH_DX — second copy on purpose:
const CATCH_DZ := 0.85   # if the window quietly widens, B here still measures 0.55/0.85
const MIN_HEIGHT_SPLIT := 0.05

var _pass := 0
var _fail := 0
var _backups : Dictionary = {}
var _guarded : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU


func _ready() -> void:
	print("=== LUMP CART COVERAGE — 2 carts (voor + achter) per laser filter, all 4 lines ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	_backup_files()
	_guard_operator_saves()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if bm == null:
		print("FATAL: BuildMode missing after boot"); _finish(); return

	for line_id in LINES.keys():
		await _place_macro(bm, String(line_id), LINES[line_id])
	# Let physics settle and LaserFilter._physics_process run its rebind
	# (immediate while unbound; the 2 s cadence only governs RE-checks).
	for _i in range(60):
		await get_tree().process_frame

	_check_coverage()
	_check_shell_clearance()

	world.queue_free()
	_verify_operator_saves()
	_finish()


func _check_coverage() -> void:
	var filters : Array = get_tree().get_nodes_in_group("laser_filter")
	var carts   : Array = get_tree().get_nodes_in_group("lump_cart")
	# lump_platform has no sim script, so no id group — find it via the
	# placeable_id meta every catalog node carries (PlaceableCatalog.gd:1105).
	var platforms : Array = []
	for po in get_tree().get_nodes_in_group("placed_object"):
		if String(po.get_meta("placeable_id", "")) == "lump_platform":
			platforms.append(po)

	_ok(filters.size() == EXPECT_FILTERS,
		"exactly %d laser filters in the world (found %d) — one per extruder line"
			% [EXPECT_FILTERS, filters.size()])
	_ok(carts.size() == EXPECT_CARTS,
		"exactly %d lump carts in the world (found %d) — voor + achter per filter"
			% [EXPECT_CARTS, carts.size()])

	# Measured context first — when a check below goes red these numbers say why.
	print("  note  : lump_platform group holds %d nodes" % platforms.size())
	for f in filters:
		var lf := f as Node3D
		var tag : String = String(lf.get_meta("macro_id")) if lf.has_meta("macro_id") else lf.name
		var aisle : Node = lf.get("lump_cart")
		var wall  : Node = lf.get("lump_cart_wall")
		print("  note  : %s filter pos %s rot_y %.3f | eject_aisle %s | eject_wall %s | cart_aisle %s | cart_wall %s"
			% [tag, str(lf.global_position.snappedf(0.01)), lf.rotation.y,
			   str((lf.call("eject_global") as Vector3).snappedf(0.01)),
			   str((lf.call("eject_global_wall") as Vector3).snappedf(0.01)),
			   str((aisle as Node3D).global_position.snappedf(0.01)) if aisle != null else "<none>",
			   str((wall as Node3D).global_position.snappedf(0.01)) if wall != null else "<none>"])
		# A — the sim's own binding resolved both nozzles, to two different carts.
		_ok(aisle != null and is_instance_valid(aisle),
			"%s: VOOR (aisle +X) nozzle has a bound cart" % tag)
		_ok(wall != null and is_instance_valid(wall),
			"%s: ACHTER (wall -X) nozzle has a bound cart" % tag)
		if aisle == null or wall == null:
			continue
		_ok(aisle != wall, "%s: the two nozzles bound two DISTINCT carts" % tag)
		# B — measured window residuals.
		var ea : Vector3 = lf.call("eject_global")
		var ew : Vector3 = lf.call("eject_global_wall")
		var pa : Vector3 = (aisle as Node3D).global_position
		var pw : Vector3 = (wall as Node3D).global_position
		_ok(absf(pa.x - ea.x) <= CATCH_DX and absf(pa.z - ea.z) <= CATCH_DZ,
			"%s: voor cart inside its catch window (dx %.2f <= %.2f, dz %.2f <= %.2f)"
				% [tag, absf(pa.x - ea.x), CATCH_DX, absf(pa.z - ea.z), CATCH_DZ])
		_ok(absf(pw.x - ew.x) <= CATCH_DX and absf(pw.z - ew.z) <= CATCH_DZ,
			"%s: achter cart inside its catch window (dx %.2f <= %.2f, dz %.2f <= %.2f)"
				% [tag, absf(pw.x - ew.x), CATCH_DX, absf(pw.z - ew.z), CATCH_DZ])
		# C — asymmetric heights: ONE cart on the 0.12 m bordes, the other on the
		# ground (operator 2026-07-15, re-confirmed 2026-08-03). MEASURED
		# 2026-08-03: under the macro rotation, the nozzle LaserFilter.gd NAMES
		# "aisle/+X/front-of-disc" physically lands on the barrel/bordes side on
		# ALL FOUR lines — i.e. the code's local labels are CROSSED relative to
		# plant vocabulary (the bordes side is the plant's ACHTERZIJDE per
		# docs/plant/extruder_line_layout.md:37-51). The PHYSICAL arrangement is
		# the operator-approved one; the label cleanup is flagged in the docs.
		# So: the lump_cart-ref ("aisle") cart must be the RAISED one.
		_ok(pa.y - pw.y >= MIN_HEIGHT_SPLIT,
			"%s: bordes-side cart (lump_cart ref) rides above the ground-side cart (%.3f - %.3f = %.3f >= %.2f)"
				% [tag, pa.y, pw.y, pa.y - pw.y, MIN_HEIGHT_SPLIT])
		# D — a bordes actually under the raised cart.
		var near_platform := false
		for p in platforms:
			var pp : Vector3 = (p as Node3D).global_position
			if Vector2(pp.x - pa.x, pp.z - pa.z).length() <= 1.0:
				near_platform = true
				break
		_ok(near_platform,
			"%s: a lump_platform bordes sits under the raised cart (XZ within 1.0 m)" % tag)


func _finish() -> void:
	_restore_files()
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _place_macro(bm, macro_id: String, start_bf: Vector2) -> void:
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[macro_id] = {}       # clean const seed, on-disk macro untouched
	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf))
	var fdir : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf + Vector2(1.0, 0.0))) - start
	fdir = fdir.normalized()
	bm.call("_build_full_line", macro_id, start, atan2(-fdir.x, -fdir.z))
	for _i in range(10):
		await get_tree().process_frame


func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null


func _restore_files() -> void:
	for p in _backups.keys():
		var orig = _backups[p]
		if orig is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f: f.store_string(orig); f.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("  (restored touched user:// files)")


func _guard_operator_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if not (fn.begins_with("allernieuwste_") and fn.ends_with(".json")):
			continue
		var f := FileAccess.open("user://" + fn, FileAccess.READ)
		if f:
			_guarded["user://" + fn] = f.get_as_text().sha256_text()
			f.close()


func _verify_operator_saves() -> void:
	var changed : Array = []
	for p in _guarded.keys():
		var f := FileAccess.open(p, FileAccess.READ)
		var h := f.get_as_text().sha256_text() if f else "<gone>"
		if f: f.close()
		if h != String(_guarded[p]):
			changed.append(p)
	if not _guarded.is_empty():
		_ok(changed.is_empty(),
			"operator allernieuwste_* saves byte-identical after the run (%d changed: %s)"
				% [changed.size(), str(changed)])


## E — no cart spawn volume may intersect the building shell. This is what made
## the first version of this test FLAKY: at bf y 62 the 3C line's bordes side
## clipped an interior shell wall (measured 2026-08-03 with an intersect_shape
## probe: the cart volume held ShellMesh/@StaticBody3D), so physics shoved the
## cart 0.2-0.3 m per run and checks B-D crossed thresholds at random. A siting
## error must be a NAMED red, not a flake.
func _check_shell_clearance() -> void:
	for f in get_tree().get_nodes_in_group("laser_filter"):
		var lf := f as Node3D
		var tag : String = String(lf.get_meta("macro_id", "")) if lf.has_meta("macro_id") else lf.name
		for side in [["voor", lf.call("eject_global") as Vector3],
				["achter", lf.call("eject_global_wall") as Vector3]]:
			var eject : Vector3 = side[1]
			var spawn := Vector3(eject.x, eject.y - 1.13 + 0.12 + 0.475, eject.z)
			var shape := BoxShape3D.new()
			shape.size = Vector3(0.85, 0.95, 1.30)
			var params := PhysicsShapeQueryParameters3D.new()
			params.shape = shape
			params.transform = Transform3D(Basis(), spawn)
			params.collide_with_areas = false
			var shell_hits : Array = []
			for h in get_tree().root.world_3d.direct_space_state.intersect_shape(params, 16):
				var col : Object = h.get("collider")
				if col is Node and String((col as Node).get_path()).contains("BuildingShell"):
					shell_hits.append(String((col as Node).get_path()))
			_ok(shell_hits.is_empty(),
				"%s: %s cart spawn volume clear of the building shell (%d hits: %s)"
					% [tag, String(side[0]), shell_hits.size(), str(shell_hits)])
