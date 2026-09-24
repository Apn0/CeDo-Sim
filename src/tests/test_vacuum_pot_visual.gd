extends Node
## VACUUM POTS, STAGE A (P3, 2026-09-23) — the extruder's two vacuum pots show
## the model's state: the melt level behind each dome's sight glass, the lid
## pushed open at capacity, the gunk at the riser.
##
##   godot --headless --path . res://src/tests/test_vacuum_pot_visual.tscn
##
## Operator rulings 2026-09-23 §14: the pots' cleaning is an operator
## mini-game (stage B, queued); this stage makes the state visible on the
## domes his 2026-07-20 photos gave the model. ExtruderModel already carries
## the state (primary/secondary_pot_fill_kg, 18 kg each, lid pushed open at
## capacity → VACUUM_ALARM, vacuum_line_gunk_kg → clean_vacuum_lines()).
##
## The production path: PlaceableCatalog.build_node attaches the SimBrain
## (MachineBrains), the brain's _process drives the catalog body every frame
## through PlaceableCatalog.set_vacuum_pot_state. The suite sets the model's
## numbers and awaits frames — no mocks.

const WATCHDOG_S := 200.0
const EXTRUDER_ID := "extruder_3a"

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

func _witness_h(root: Node3D) -> float:
	for h in root.get_children():
		if h.has_meta("win_bottom_y"):
			var wit := h.get_node_or_null("LevelWitness") as MeshInstance3D
			if wit != null and wit.visible:
				return (wit.mesh as BoxMesh).size.y
			return 0.0
	return -1.0

func _frames(n: int) -> void:
	for _i in n:
		await get_tree().process_frame

func _run() -> void:
	print("[TEST] vacuum pots stage A — P3")
	var body : Node3D = PlaceableCatalog.build_node(EXTRUDER_ID, false)
	_check(body != null, "F1 catalog built %s" % EXTRUDER_ID)
	if body == null:
		_finish(); return
	add_child(body)
	await _frames(3)
	var brain : Node = null
	for m in get_tree().get_nodes_in_group("extruder_machine"):
		if m.get_parent() == body:
			brain = m
	_check(brain != null, "F1 the SimBrain is attached under the body")
	if brain == null:
		_finish(); return
	var model = brain.get("model")
	_check(model != null, "F1 the brain owns an ExtruderModel")
	if model == null:
		_finish(); return
	var roots := {}
	for nm in ["primary", "secondary"]:
		roots[nm] = body.find_child("VacPot_" + nm, true, false)
	_check(roots["primary"] != null and roots["secondary"] != null, "F1 two pot roots exist (VacPot_primary, VacPot_secondary)")
	if roots["primary"] == null or roots["secondary"] == null:
		_finish(); return
	for nm in ["primary", "secondary"]:
		var r : Node3D = roots[nm]
		_check(r.get_node_or_null("Lid") != null and r.get_node_or_null("Gunk") != null and _witness_h(r) >= 0.0,
			"F1 %s pot has a Lid, a Gunk deposit and a level witness" % nm)
		var base : float = float(r.get_meta("silo_fill_base_y"))
		var rng : float = float(r.get_meta("silo_fill_range_y"))
		var wb : float = -1.0
		var wt : float = -1.0
		for h in r.get_children():
			if h.has_meta("win_bottom_y"):
				wb = float(h.get_meta("win_bottom_y"))
				wt = float(h.get_meta("win_top_y"))
		_check(wb > base and wt < base + rng, "F1 %s pot's sight glass lies inside the pot's level range" % nm)
	var primary : Node3D = roots["primary"]
	var secondary : Node3D = roots["secondary"]
	var lid_p := primary.get_node("Lid") as MeshInstance3D
	var lid_s := secondary.get_node("Lid") as MeshInstance3D
	var closed_y : float = float(lid_p.get_meta("lid_closed_y"))
	# Rulings §20 (2026-09-24): the lid is on the pot's FRONT face (+X). Closed
	# it sits on its seat (meta lid_home) as a vertical disc (rotation.z = 90°);
	# pushed open by the melt it moves OUT along +X and tilts.
	var home_p : Vector3 = lid_p.get_meta("lid_home")
	var home_s : Vector3 = lid_s.get_meta("lid_home")
	# ── empty ──
	model.primary_pot_fill_kg = 0.0
	model.secondary_pot_fill_kg = 0.0
	model.vacuum_line_gunk_kg = 0.0
	await _frames(2)
	_check(_witness_h(primary) == 0.0 and _witness_h(secondary) == 0.0, "S1 empty pots: both glasses dark")
	_check(lid_p.position.distance_to(home_p) < 1e-6 and absf(lid_p.rotation.z - PI * 0.5) < 1e-6 and absf(home_p.y - closed_y) < 1e-6,
		"S1 lid closed on its seat on the front face (a vertical disc)")
	_check(not (primary.get_node("Gunk") as MeshInstance3D).visible, "S1 no gunk")
	# ── primary half full ──
	var cap : float = ExtruderModel.VACUUM_POT_CAPACITY_KG
	model.primary_pot_fill_kg = cap * 0.5
	await _frames(2)
	var h_half : float = _witness_h(primary)
	_check(h_half > 0.0 and h_half < 0.06, "S2 primary at 50 %%: the level line is in the glass (%.3f of 0.06 m)" % h_half)
	_check(_witness_h(secondary) == 0.0, "S2 secondary still dark")
	_check(lid_p.position.distance_to(home_p) < 1e-6, "S2 lid still closed below capacity")
	# ── primary at capacity: the melt pushes the lid open ──
	model.primary_pot_fill_kg = cap
	await _frames(2)
	_check(absf(_witness_h(primary) - 0.06) < 1e-4, "S3 primary full: glass full")
	_check(lid_p.position.x > home_p.x + 0.05 and absf(lid_p.rotation.z - PI * 0.5) > 0.3, "S3 lid pushed open OUT of the front face (%.2f m out, tilted)" % (lid_p.position.x - home_p.x))
	_check(lid_s.position.distance_to(home_s) < 1e-6, "S3 secondary lid stays closed")
	_check(bool(primary.get_meta("lid_open")) and not bool(secondary.get_meta("lid_open")), "S3 roots record which lid is open")
	# ── gunk grows and is cleaned ──
	model.vacuum_line_gunk_kg = ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG * 0.5
	await _frames(2)
	var gunk := primary.get_node("Gunk") as MeshInstance3D
	_check(gunk.visible and absf(gunk.scale.x - 0.5) < 1e-4, "S4 gunk at half the dismantle threshold: visible at scale %.2f" % gunk.scale.x)
	model.call("clean_vacuum_lines")
	await _frames(2)
	_check(not gunk.visible, "S4 clean_vacuum_lines() clears the deposit")
	# ── emptied pot: lid back down, glass dark ──
	model.primary_pot_fill_kg = 0.0
	await _frames(2)
	_check(lid_p.position.distance_to(home_p) < 1e-6 and _witness_h(primary) == 0.0, "S5 emptied: lid back on its seat, glass dark")
	# ── a ghost has none of it ──
	var ghost : Node3D = PlaceableCatalog.build_node(EXTRUDER_ID, true)
	_check(ghost != null and ghost.find_child("VacPot_primary", true, false) == null, "N1 a build-mode ghost carries no pot roots")
	if ghost != null:
		ghost.free()
	body.queue_free()
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
