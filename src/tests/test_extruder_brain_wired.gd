extends Node

# =============================================================================
# Proof that a placed extruder actually simulates.
# =============================================================================
# Regression guard for the gap measured on 2026-08-11: a booted MainWorld on a
# real 84-placeable save contained 8872 nodes across 67 scripts and ZERO
# ExtruderMachine.gd, and a 90-second recording of every EventBus signal
# produced 0 events. The catalog's extruder_3a was geometry; nothing in a
# configured world ever constructed an ExtruderModel, so the vacuum cascade,
# the HMI MACHINES screen and the per-scope laser-filter lookup all had nothing
# to bind to. PlaceableCatalog.build_node now calls MachineBrains.attach().
# (Not the SWI-049 startup flow — that is the SORTING line; see MachineBrains.)
#
# The repo's own regression harness (tools/regression/run.sh) does NOT cover
# this: its world places no extruder at all ("extruder" appears zero times in
# its output), so it stayed green throughout the entire period the brain was
# missing. That is why this file exists separately.
#
#   godot --headless --path . res://src/tests/test_extruder_brain_wired.tscn
#
# Exits 0 on pass, 1 on failure.
# =============================================================================

const TEST_SLOT   : String = "__extruderwired__"
const BOOT_FRAMES : int = 120
const SETTLE_FRAMES : int = 60
const EXTRUDER_ID : String = "extruder_3a"

var _protect : Array[String] = []
var _backups : Dictionary = {}
var _world : Node = null
var _oks : int = 0
var _fails : int = 0


func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)


func _ready() -> void:
	print("=== extruder brain wiring proof ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return

	_protect = [
		"user://world_layout.json",
		"user://%s_save.json" % TEST_SLOT,
		"user://%s_factory.json" % TEST_SLOT,
	]
	_backup_files()

	# ── unit level: the mapping, with a negative control ─────────────────────
	# Without the negative control this file would pass on an attach() that
	# bolts a brain onto every placeable in the game.
	_check(MachineBrains.has_brain(EXTRUDER_ID), "%s is known to own a brain" % EXTRUDER_ID)
	_check(not MachineBrains.has_brain("flotation_tank"),
		"a non-extruder placeable (flotation_tank) is NOT given a brain")
	_check(not MachineBrains.has_brain("extruder_silo"),
		"extruder_silo is NOT given a brain (it is a feed silo, not an extruder)")

	var built := PlaceableCatalog.build_node(EXTRUDER_ID, false)
	_check(built != null, "catalog built %s" % EXTRUDER_ID)
	if built != null:
		var brain := built.get_node_or_null("SimBrain")
		_check(brain != null, "the built body carries a SimBrain child")
		# Idempotence: a second attach on the same body must not stack.
		MachineBrains.attach(built, EXTRUDER_ID, Vector3(2.6, 4.2, 14.0))
		var n_brains := 0
		for ch in built.get_children():
			if String(ch.name).begins_with("SimBrain"):
				n_brains += 1
		_check(n_brains == 1, "attach() is idempotent (%d SimBrain child)" % n_brains)
		built.queue_free()

	var ghost := PlaceableCatalog.build_node(EXTRUDER_ID, true)
	if ghost != null:
		_check(ghost.get_node_or_null("SimBrain") == null,
			"the build-mode GHOST gets no brain")
		ghost.queue_free()

	# ── world level: does it survive a real MainWorld boot ───────────────────
	var bus := get_node_or_null("/root/EventBus")
	bus.set_meta("pending_save_name", TEST_SLOT)
	bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load")
		_finish(2)
		return
	_world = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()
	for _i in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	_check(WorldLayout.is_configured(),
		"the world under test is CONFIGURED (the case that was broken; an "
		+ "unconfigured world spawns the legacy brain and would pass for free)")

	var machines := get_tree().get_nodes_in_group("extruder_machine")
	_check(machines.size() > 0,
		"the 'extruder_machine' group is populated (%d) — HmiOverlay "
		% machines.size() + "enumerates this group in five places")

	# Distinct config instances: two placeables must not share one resource, or
	# editing a zone setpoint on the HMI would retune the other machine too.
	var cfg_ids := {}
	var ok_ids := true
	for m in machines:
		var cfg = m.get("config_resource")
		if cfg == null:
			ok_ids = false
			continue
		cfg_ids[cfg.get_instance_id()] = true
		var lid := String(cfg.get("line_id"))
		if lid == "" or lid == "3B" and EXTRUDER_ID == "extruder_3a":
			# 3B is the scene default; seeing it on a 3A placeable means the
			# config was assigned after _ready() and the model never saw it.
			ok_ids = false
	_check(ok_ids, "every brain carries a line id from its placeable, not the "
		+ "scene default")
	_check(cfg_ids.size() == machines.size(),
		"each brain has its OWN ExtruderConfig instance (%d configs / %d brains)"
		% [cfg_ids.size(), machines.size()])

	# ── behaviour: it must actually tick, not merely exist ───────────────────
	var seen := {"n": 0}
	bus.machine_state_changed.connect(func(_a, _b, _c): seen["n"] += 1)
	var driven := false
	for m in machines:
		var pend = m.get("_pending")
		if pend != null:
			pend["start_production"] = true
			driven = true
	_check(driven, "the brain exposes the same _pending dict the E key writes to")
	for _i in range(90):
		await get_tree().process_frame
	_check(seen["n"] > 0,
		"driving start_production produced %d machine_state_changed event(s) — "
		% seen["n"] + "the model is really ticking")

	await _check_preheat()
	_finish(0 if _fails == 0 else 1)


## The warm-up, exercised on a bare model so the timing is exact.
##
## Before this existed a cold barrel was a dead end: melt starts at ambient,
## _tick_off cools toward ambient, and no operator input turned the heaters on,
## so pressing start guaranteed a torque trip 2 s later. Measured over a
## recorded shift: 81 % of starts on 3A and 98 % on L1 went STARTING -> FAULT.
func _check_preheat() -> void:
	print("  -- warm-up (Cedo-PROD-SWI-042 p4 step 19: >= 30 min) --")
	var cfg := ExtruderConfig.new()
	var m := ExtruderModel.new(cfg)
	m.melt_temp = ExtruderModel.AMBIENT_C
	_check(not m.preheat_ready(), "a cold barrel reports NOT ready")

	# Cold start must not walk into the trip.
	var ev: Array[String] = m.tick(0.1, {"start_production": true})
	_check(m.state == ExtruderModel.State.PREHEAT,
		"pressing start on a cold barrel routes to PREHEAT, not STARTING")

	var dt := 1.0
	var elapsed := 0.0
	var ready_at := -1.0
	var guard := 0
	while guard < 200000:
		guard += 1
		ev = m.tick(dt, {})
		elapsed += dt
		if m.preheat_ready():
			ready_at = elapsed
			break
	_check(ready_at > 0.0, "the barrel does reach temperature (%.0f s)" % ready_at)
	_check(ready_at >= cfg.preheat_min_s * 0.5,
		"warm-up took %.0f s, i.e. %.0f min — the documented minimum is 30 min "
		% [ready_at, ready_at / 60.0] + "to setpoint")
	_check(m.state == ExtruderModel.State.PREHEAT,
		"it stays in PREHEAT until the operator presses green")

	# Green button live only when ready — check the negative first.
	var m2 := ExtruderModel.new(ExtruderConfig.new())
	m2.melt_temp = ExtruderModel.AMBIENT_C
	m2.tick(0.1, {"start_production": true})
	m2.tick(0.1, {"start_production": true})
	_check(m2.state == ExtruderModel.State.PREHEAT,
		"pressing green while still cold does NOT start the line")

	# ...and the positive.
	ev = m.tick(0.1, {"start_production": true})
	_check(m.state == ExtruderModel.State.STARTING,
		"pressing green once ready enters STARTING")

	# The whole point: a warm start must not trip.
	var tripped := false
	for _i in range(600):
		var e2: Array[String] = m.tick(0.1, {})
		if m.state == ExtruderModel.State.FAULT:
			tripped = true
			break
		if m.state == ExtruderModel.State.RUNNING:
			break
	_check(not tripped and m.state == ExtruderModel.State.RUNNING,
		"a preheated start reaches RUNNING without a torque trip (state=%d)"
		% m.state)

	# Regression guard on the enum: PREHEAT must stay appended, because saves
	# and recorded event streams carry the first eight by number.
	_check(int(ExtruderModel.State.OFF) == 0 and int(ExtruderModel.State.FAULT) == 6
		and int(ExtruderModel.State.EMERGENCY_STOP) == 7
		and int(ExtruderModel.State.PREHEAT) == 8,
		"State enum numbering unchanged, PREHEAT appended as 8")

	# Vacuum lines maintenance test
	var vm := ExtruderModel.new(ExtruderConfig.new())
	vm.vacuum_line_gunk_kg = 5.2
	vm.flooded_dismantle_required = true
	var evs := vm.tick(0.1, {"clean_vacuum_lines": true})
	_check(vm.vacuum_line_gunk_kg == 0.0 and not vm.flooded_dismantle_required,
		"clean_vacuum_lines resets gunk to 0 and clears dismantle flag")
	_check(evs.has("vacuum_lines_cleaned"), "emits vacuum_lines_cleaned event on tick")


func _backup_files() -> void:
	for p in _protect:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				_backups[p] = f.get_buffer(f.get_length())
				f.close()


func _restore_files() -> void:
	for p in _protect:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(data)
				f.close()


func _finish(code: int) -> void:
	_restore_files()
	print("Result: %s (%d ok, %d fail)"
		% ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("RESULT: %s" % ["PASS" if _fails == 0 else "FAIL"])
	get_tree().quit(code)
