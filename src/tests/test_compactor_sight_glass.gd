extends Node
## COMPACTOR KIJKGLAS LEVEL (2026-09-23) — what shows behind the compactor's
## sight glass is the pot's real load.
##
##   godot --headless --path . res://src/tests/test_compactor_sight_glass.tscn
##
## Cedo PROD-SWI-012 p7 step 6: "Vul de compactor op hand tot het kijkglas" —
## the sight glass on the cleanout door is the operator's fill reference. The
## model already had the glass (PlaceableCatalog._m_compactor) and the load
## (CutterCompactor.charge / POT_CAPACITY_KG); nothing connected them. Now a
## PotFill flake column stands on the cutter disc, sized by
## PlaceableCatalog.set_pot_fill(), which LineFlow calls every tick with
## CutterCompactor.pot_fill_fraction().
##
## S1/S2 read the column's geometry off the mesh's own meta (never a copied
## constant) and check the glass window actually lies inside the fill range —
## otherwise "fill up to the glass" could never be done. S3 is the production
## path: a real LineFlow node for the catalog compactor, material injected into
## its input buffer, the column tracking the model tick by tick.

const WATCHDOG_S := 150.0
const TICK_S := 0.1

var _fails := 0
var _oks := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _height(fill: MeshInstance3D) -> float:
	var cm := fill.mesh as CylinderMesh
	return cm.height if cm != null else -1.0

func _run() -> void:
	print("[TEST] compactor kijkglas level")
	var m : Node3D = PlaceableCatalog.build_node("compactor", false)
	_check(m != null, "S1 catalog built the 3C compactor (PCU)")
	if m == null:
		_finish(); return
	add_child(m)
	await get_tree().process_frame
	var fill : MeshInstance3D = m.find_child("PotFill", true, false) as MeshInstance3D
	_check(fill != null, "S1 the compactor carries a PotFill column")
	if fill == null:
		_finish(); return
	_check(not fill.visible, "S1 empty pot: the column is hidden")
	var base : float = float(fill.get_meta("pot_fill_base_y", -1.0))
	var rng  : float = float(fill.get_meta("pot_fill_range_y", -1.0))
	var gy   : float = float(fill.get_meta("kijkglas_y", -1.0))
	var gr   : float = float(fill.get_meta("kijkglas_r", -1.0))
	_check(base > 0.0 and rng > 0.5 and gy > 0.0 and gr > 0.0,
		"S1 column geometry on the mesh's meta: base %.3f m, range %.3f m, glass at %.3f ± %.2f m" % [base, rng, gy, gr])
	var f_lo : float = ((gy - gr) - base) / rng
	var f_hi : float = ((gy + gr) - base) / rng
	_check(f_lo > 0.0 and f_hi < 1.0 and f_lo < f_hi,
		"S1 the kijkglas lies INSIDE the fill range: the level enters the glass at %.0f %% and leaves it at %.0f %% of the pot" % [f_lo * 100.0, f_hi * 100.0])
	var ghost : Node3D = PlaceableCatalog.build_node("compactor", true)
	_check(ghost != null and ghost.find_child("PotFill", true, false) == null, "S1 a build-mode ghost gets no column")
	if ghost != null:
		ghost.free()

	# ── S2: the sizing rule ──
	var r50 := PlaceableCatalog.set_pot_fill(m, 0.5)
	_check(r50 == fill and fill.visible, "S2 set_pot_fill(0.5) shows the column and returns it")
	_check(absf(_height(fill) - 0.5 * rng) < 1.0e-5, "S2 half-full: height %.4f == 0.5 × range %.4f" % [_height(fill), rng])
	var top50 : float = fill.position.y + _height(fill) * 0.5
	_check(absf(top50 - (base + 0.5 * rng)) < 1.0e-5, "S2 half-full: column stands on the base (top at %.4f, base+half %.4f)" % [top50, base + 0.5 * rng])
	PlaceableCatalog.set_pot_fill(m, 1.0)
	var top100 : float = fill.position.y + _height(fill) * 0.5
	_check(absf(top100 - (base + rng)) < 1.0e-5, "S2 full: top at %.4f == base + range %.4f" % [top100, base + rng])
	PlaceableCatalog.set_pot_fill(m, 1.7)
	_check(absf(_height(fill) - rng) < 1.0e-5, "S2 an over-full fraction is clamped to the lid (%.4f)" % _height(fill))
	PlaceableCatalog.set_pot_fill(m, 0.0)
	_check(not fill.visible, "S2 set_pot_fill(0) hides it again")
	var f_glass : float = 0.5 * (f_lo + f_hi)
	PlaceableCatalog.set_pot_fill(m, f_glass)
	var top_g : float = fill.position.y + _height(fill) * 0.5
	_check(absf(top_g - gy) <= gr, "S2 at %.0f %% the level shows in the glass (top %.3f vs glass %.3f ± %.2f)" % [f_glass * 100.0, top_g, gy, gr])
	PlaceableCatalog.set_pot_fill(m, 0.0)
	_check(PlaceableCatalog.set_pot_fill(Node3D.new(), 0.5) == null, "S2 a machine without a column returns null, no error")

	# ── S3: the production path — LineFlow drives it from the compactor model ──
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var ci := -1
	for i in nodes.size():
		if (nodes[i] as Dictionary).get("node", null) == m:
			ci = i
	_check(ci >= 0, "S3 LineFlow built a node for the placed compactor (%d nodes)" % nodes.size())
	if ci < 0:
		_finish(); return
	var nd : Dictionary = nodes[ci]
	var cc = nd.get("cc")
	_check(cc != null, "S3 the node carries a CutterCompactor model (cc)")
	if cc == null:
		_finish(); return
	lf.call("start_line")
	for _i in 260:
		lf.call("tick", TICK_S)
	_check(bool(nd["powered"]), "S3 compactor powered after line start")
	# LineFlow's own head feed already put material into a lone head node during
	# the start-up ticks (measured: the pot read 100 % here), so the pre-injection
	# check is consistency, not emptiness.
	var f0 : float = float(cc.call("pot_fill_fraction"))
	_check(absf(float(nd.get("cc_fill", -1.0)) - f0) < 1.0e-9 and fill.visible == (f0 * rng > 0.002),
		"S3 after line start the published cc_fill and the column's visibility agree with the model (fill %.1f %%)" % (f0 * 100.0))
	var bin : MaterialBatch = nd.get("in", null) as MaterialBatch
	bin.add(MaterialBatch.new(60.0, 60.0 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
	var mismatches := 0
	var max_frac := 0.0
	var first_h := -1.0
	var last_h := -1.0
	for _i in 300:
		lf.call("tick", TICK_S)
		var frac : float = float(cc.call("pot_fill_fraction"))
		max_frac = maxf(max_frac, frac)
		if absf(float(nd.get("cc_fill", -1.0)) - frac) > 1.0e-9:
			mismatches += 1
		var want_h : float = frac * rng
		if want_h > 0.002:
			if not fill.visible or absf(_height(fill) - want_h) > 1.0e-4:
				mismatches += 1
			if first_h < 0.0:
				first_h = _height(fill)
			last_h = _height(fill)
		elif fill.visible:
			mismatches += 1
	_check(max_frac > 0.05, "S3 anti-vacuity: material reached the pot (peak fill %.1f %% of %.0f kg)" % [max_frac * 100.0, cc.POT_CAPACITY_KG])
	_check(mismatches == 0, "S3 over 300 ticks the column height == pot_fill_fraction × range every tick and nd.cc_fill matches (%d mismatches)" % mismatches)
	_check(first_h >= 0.0 and last_h >= 0.0 and absf(last_h - first_h) > 1.0e-4,
		"S3 the level moved while the pot was fed and discharged (%.4f → %.4f m)" % [first_h, last_h])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] compactor kijkglas level %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
