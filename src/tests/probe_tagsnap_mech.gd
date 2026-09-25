extends Node3D
## MEASUREMENT PROBE — the doseersilo overload e-stop in test_tag_snapshot.
## Three modes, selected by the first arg after "--":
##   A (default) — mirror the test exactly: 400 x lf.tick(0.1) in a TIGHT loop,
##                 zero engine frames between ticks.
##   B "frames"  — identical, but await one process_frame between ticks, so
##                 RotatingMechanism._process gets to ramp _rpm_cur.
##   C "nomech"  — tight loop again, but nd["mech"]/nd["mechs"] nulled after
##                 rebuild, so _mech_fraction() returns 1.0 as it did before the
##                 recursive-discovery fix.
## Prints measurements only; the caller compares runs. No assert().

# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")
const LINE_3C_START_BF := Vector2(4.0, 44.0)   # as test_tag_snapshot
const TICK_DT := 0.1
const TICK_COUNT := 400
const FEED_RATE := 8.0
const FEED_DENSITY := 320.0
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}
const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__mechprobe___save.json", "user://__mechprobe___factory.json",
]

var _backups : Dictionary = {}
var _mode := "A"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		if String(args[0]) == "frames":
			_mode = "B"
		elif String(args[0]) == "nomech":
			_mode = "C"
		elif String(args[0]) == "census":
			_mode = "CENSUS"
		elif String(args[0]) == "census_frames":
			_mode = "CENSUS_FRAMES"
	print("=== MECH PROBE mode %s ===" % _mode)
	_backup_files()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", "__mechprobe__")
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame
	var lf = world.get("line_flow")
	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if lf == null or bm == null:
		print("FATAL: no LineFlow/BuildMode"); _finish(world); return

	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache["line_3c"] = {}
	var fr : Dictionary = await BFrame.wait_fitted(bm)
	var start : Vector3 = BFrame.to_scene(fr, LINE_3C_START_BF, Plant.floor_top_y())
	var fdir : Vector3 = BFrame.to_scene(fr, LINE_3C_START_BF + Vector2(1.0, 0.0), Plant.floor_top_y()) - start
	fdir = fdir.normalized()
	bm.call("_build_full_line", "line_3c", start, atan2(-fdir.x, -fdir.z))
	for _i in range(10):
		await get_tree().process_frame
	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame

	var nodes : Array = lf.get("_nodes")
	var d_idx := -1
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("l3c_code", "")) == "L3C.1":
			d_idx = i
			break
	if d_idx < 0:
		print("FATAL: no L3C.1 node"); _finish(world); return
	var nd : Dictionary = nodes[d_idx]

	if _mode == "C":
		var n_null := 0
		for ndc in nodes:
			(ndc as Dictionary)["mech"] = null
			(ndc as Dictionary)["mechs"] = []
			n_null += 1
		print("  C: nulled mech/mechs on %d nodes" % n_null)

	var mechs : Array = nd.get("mechs", [])
	print("  pre : mech=%s mechs=%d rate=%.2f" % [
		"null" if nd.get("mech") == null else "set", mechs.size(), float(nd["rate"])])
	for m in mechs:
		if m != null and is_instance_valid(m):
			print("  pre : rotor '%s' current_rpm=%.2f nominal=%.2f running=%s" % [
				String(m.name), float(m.call("current_rpm")), float(m.get("nominal_rpm")),
				str(m.get("running"))])

	lf.call("start_line")
	for t in range(TICK_COUNT):
		var fed := 0.0
		for i2 in nodes.size():
			var nf : Dictionary = nodes[i2]
			if String(nf["role"]) == "sink":
				continue
			if bool(lf.call("_has_incoming", i2)):
				continue
			var draw : float = FEED_RATE * TICK_DT
			(nf["in"] as MaterialBatch).add(MaterialBatch.new(
				draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "probe_feed",
				draw * 0.08, draw * 0.12))
			fed += draw
		lf.call("tick", TICK_DT)
		if _mode == "B" or _mode == "CENSUS_FRAMES":
			await get_tree().process_frame
		if t % 50 == 0 or t == TICK_COUNT - 1:
			var mr := -1.0
			var mech = nd.get("mech")
			if mech != null and is_instance_valid(mech):
				mr = float(mech.call("current_rpm"))
			print("  t=%5.1fs powered=%s spin=%.2f mech_rpm=%7.2f frac=%.3f buffer=%8.2f estop=%s" % [
				(t + 1) * TICK_DT, str(bool(nd["powered"])), float(nd["spin"]), mr,
				float(lf.call("_mech_fraction", nd)), float(nd["buffer"]),
				str(bool(lf.call("is_estopped")))])
	print("  VERDICT mode %s: estop=%s fault_id='%s' doseersilo buffer=%.2f powered=%s" % [
		_mode, str(bool(lf.call("is_estopped"))), String(lf.call("estop_fault_id")),
		float(nd["buffer"]), str(bool(nd["powered"]))])
	if _mode.begins_with("CENSUS"):
		print("  ── node census after the drive (every LineFlow node) ──")
		for i3 in nodes.size():
			var nc : Dictionary = nodes[i3]
			var fed_flag : String = "FED " if (String(nc["role"]) != "sink" and not bool(lf.call("_has_incoming", i3))) else "    "
			var mcs : Array = nc.get("mechs", [])
			print("  %2d %s%-24s %-8s role=%-9s rate=%5.2f powered=%-5s spin=%.2f frac=%.3f buf=%8.2f mechs=%d" % [
				i3, fed_flag, String(nc["id"]), String(nc.get("l3c_code", "")),
				String(nc["role"]), float(nc["rate"]), str(bool(nc["powered"])),
				float(nc["spin"]), float(lf.call("_mech_fraction", nc)),
				float(nc["buffer"]), mcs.size()])
			for m3 in mcs:
				if m3 != null and is_instance_valid(m3):
					print("        rotor '%s' rpm_setpoint=%.2f nominal=%.2f current=%.2f running=%s cap=%.2f comp=%s" % [
						String(m3.name), float(m3.get("rpm")), float(m3.get("nominal_rpm")),
						float(m3.call("current_rpm")), str(m3.get("running")),
						float(m3.get("capacity_kg_s")),
						String(m3.get_meta("comp")) if m3.has_meta("comp") else "-"])
	_finish(world)

func _finish(world: Node) -> void:
	if world != null:
		world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(0)

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
