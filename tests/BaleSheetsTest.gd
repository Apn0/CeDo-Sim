extends SceneTree
## Headless verification of the sheet + wire + cut features added to bales.
## Pure script mode — works on any Godot 4.x install.

const _BaleDefs := preload("res://src/sim/BaleDefs.gd")
const _Catalog  := preload("res://src/build/PlaceableCatalog.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Sheet bales + wires + cut state test")
	print("============================================================")

	_test_sheet_decomposition()
	_test_wires_structure()
	_test_cut_meta_flips()
	_test_clamp_force_metadata()

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

func _ok_approx(actual: float, expected: float, tol: float, label: String) -> void:
	var ok := absf(actual - expected) <= tol
	if not ok:
		label = "%s  (expected ~%.4f ±%.4f, got %.4f)" % [label, expected, tol, actual]
	_ok(ok, label)

# =============================================================================
# 1) Sheet count + total thickness ≈ bale length (inset 2%)
# =============================================================================
func _test_sheet_decomposition() -> void:
	print("[1] Sheet decomposition")
	for bale_def in _BaleDefs.origins():
		var id := String(bale_def["id"])
		var size: Vector3 = bale_def["size"]
		var bale = _Catalog.build_node(id, false)
		_ok(bale != null, "%s bale builds" % id)
		if bale == null:
			continue
		var sheets := bale.find_child("Sheets", true, false)
		_ok(sheets != null, "%s bale exposes Model/Sheets" % id)
		if sheets == null:
			continue
		# Count only nodes named Sheet_NN — the Sheets group also holds the
		# random film-patch overlays, which are mesh children but not sheets.
		var sheet_meshes : Array = []
		for c in sheets.get_children():
			if c is MeshInstance3D and String((c as Node).name).begins_with("Sheet_"):
				sheet_meshes.append(c)
		var declared_count: int = int(bale.get_meta("sheet_count", 0))
		_ok(declared_count >= 30 and declared_count <= 60,
			"%s sheet_count meta in [30, 60] = %d" % [id, declared_count])
		_ok(sheet_meshes.size() == declared_count,
			"%s drew %d sheet meshes (== sheet_count)" % [id, sheet_meshes.size()])
		# Each sheet is inset 5% in X for the wire wrap; total ≈ 0.95 × inner_len
		# = 0.95 × 0.98 × size.x ≈ 0.931 × size.x
		var total_thickness := 0.0
		for sm in sheet_meshes:
			total_thickness += ((sm as MeshInstance3D).mesh as BoxMesh).size.x
		var expected := 0.98 * 0.95 * size.x
		_ok_approx(total_thickness, expected, expected * 0.05,
			"%s total sheet thickness ≈ 0.93 × bale length" % id)
		bale.queue_free()

# =============================================================================
# 2) Wires: 3 wires, each with top/right/bottom/left segments
# =============================================================================
func _test_wires_structure() -> void:
	print("[2] Wire structure (3 wires × 4 segments)")
	var bale = _Catalog.build_node("rotterdam", false)
	if bale == null:
		_ok(false, "rotterdam bale built for wire test")
		return
	var wires := bale.find_child("Wires", true, false)
	_ok(wires != null, "bale exposes Model/Wires")
	if wires != null:
		var wire_nodes : Array = []
		for c in wires.get_children():
			if (c as Node).name.begins_with("Wire_"):
				wire_nodes.append(c)
		_ok(wire_nodes.size() == 3, "exactly 3 wires (= %d)" % wire_nodes.size())
		for w in wire_nodes:
			var top    := (w as Node).get_node_or_null("Top")
			var bot    := (w as Node).get_node_or_null("Bottom")
			var right_ := (w as Node).get_node_or_null("Right")
			var left_  := (w as Node).get_node_or_null("Left")
			_ok(top != null and bot != null and right_ != null and left_ != null,
				"%s has Top/Bottom/Right/Left" % (w as Node).name)
	bale.queue_free()

# =============================================================================
# 3) Cut state: removing Wire_i children + flipping meta mirrors the
#    BaleClamp._try_cut_wires() effect.
# =============================================================================
func _test_cut_meta_flips() -> void:
	print("[3] Wire-cut meta lifecycle")
	var bale = _Catalog.build_node("zwolle", false)
	if bale == null:
		_ok(false, "zwolle bale built for cut test")
		return
	_ok(bale.get_meta("wires_cut") == false, "starts wires_cut = false")
	# Simulate the cut (what BaleClamp._try_cut_wires() does at runtime)
	var wires := bale.find_child("Wires", true, false)
	if wires != null:
		for child in wires.get_children():
			child.queue_free()
	bale.set_meta("wires_cut", true)
	_ok(bale.get_meta("wires_cut") == true, "wires_cut flips to true after cut")
	# queue_free() is deferred — by the next idle frame the children are gone,
	# but in this test we don't run a frame, so we count only children that
	# AREN'T pending deletion.
	var alive := 0
	if wires != null:
		for c in wires.get_children():
			if not c.is_queued_for_deletion():
				alive += 1
	_ok(wires != null and alive == 0,
		"after cut: all wires queued for deletion (sheets still bound until release)")
	bale.queue_free()

# =============================================================================
# 4) Per-origin clamp-force metadata: lighter bales need less force; the
#    wire compliance threshold must be reachable (< 1.0).
# =============================================================================
func _test_clamp_force_metadata() -> void:
	print("[4] Clamp force metadata")
	for bale_def in _BaleDefs.origins():
		var id := String(bale_def["id"])
		var bale = _Catalog.build_node(id, false)
		if bale == null:
			continue
		var needed: float = float(bale.get_meta("clamp_force_needed", -1.0))
		var compliance: float = float(bale.get_meta("wire_compliance", -1.0))
		_ok(needed > 0.0 and needed < 1.0,
			"%s clamp_force_needed in (0, 1) = %.2f" % [id, needed])
		_ok(compliance > 0.0 and compliance < 1.0,
			"%s wire_compliance in (0, 1) = %.2f" % [id, compliance])
		_ok(needed < compliance,
			"%s: clamp force to LIFT (%.2f) < force that BULGES wires (%.2f)"
				% [id, needed, compliance])
		bale.queue_free()
