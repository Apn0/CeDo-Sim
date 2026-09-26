extends Node
## PROBE (not a suite): line 1 in a real MainWorld save slot, bales to weegschaal.
##
##   APPDATA=<scratch copy holding the slot> godot --headless --fixed-fps 60 --path . \
##       res://src/tests/probe_line1_playtest.tscn -- [slot] [sim seconds] [bales]
##
## Loads the slot the way the main menu does (EventBus meta "pending_save_name"),
## presses line 1's extruder start button the way the HMI does
## (`_pending["start_production"]`), starts the line, drops Rotterdam bales on the
## line's feed head, and prints every 10 s of sim time where the kg are: fed, at
## the extruder, on the pellet side (laser filter, heetafslag, centrifuge,
## weegschaal) and banked past the weegschaal.
##
## PROBE-ONLY SHORTCUT: the barrel is held at its preheat-ready melt temperature
## until the screw turns, instead of the 1800 s warm-up (SWI-042 p4 §19); the
## warm-up itself is test_extruder_start_interlock's. Everything else is the
## production path. Run it with --fixed-fps 60 so sim time does not wait on the
## wall clock.

const WATCH_IDS := ["opzetband_1", "shredder_1", "extruder_silo", "compactorband",
	"extruder_1", "laser_filter", "heetafslag", "centrifuge", "weegschaal", "voorraad_silo"]

var _frames : int = 0
var _frame_limit : int = 0

func _process(_d: float) -> void:
	_frames += 1
	if _frame_limit > 0 and _frames > _frame_limit:
		print("PROBE RESULT: WATCHDOG, %d frames" % _frames)
		get_tree().quit(2)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var slot : String = args[0] if args.size() > 0 else "line1_playtest"
	var secs : float = float(args[1]) if args.size() > 1 else 900.0
	var bales : int = int(args[2]) if args.size() > 2 else 2
	_frame_limit = int((secs + 300.0) * 60.0)
	EventBus.set_meta("pending_save_name", slot)
	EventBus.set_meta("pending_is_new_save", false)   # a LOAD, as MainMenu sets it; true wipes the factory file
	var world : Node = load("res://src/scenes/world/MainWorld.tscn").instantiate()
	add_child(world)
	var lf : Node = null
	for i in 3000:
		await get_tree().process_frame
		lf = _find_script(world, "LineFlow.gd")
		if lf != null and (lf.get("_nodes") as Array).size() > 0:
			break
	if lf == null:
		print("PROBE RESULT: no LineFlow after boot"); get_tree().quit(1); return
	for i in 60:
		await get_tree().process_frame
	var nodes : Array = lf.get("_nodes")
	var ext_brains := get_tree().get_nodes_in_group("extruder_machine")
	print("[probe] slot %s: %d LineFlow nodes, %d extruder brains %s" % [slot, nodes.size(),
		ext_brains.size(), str(ext_brains.map(func(b): return String(b.config_resource.line_id)))])
	if ext_brains.is_empty():
		print("PROBE RESULT: no extruder brain"); get_tree().quit(1); return
	var brain = ext_brains[0]
	var m = brain.get("model")

	# 1) extruder first (SWI-042: the silos fill during its warm-up), shortcut on the warm-up
	var t0 := Time.get_ticks_msec()
	var pressed := false
	for i in 60 * 120:
		if m.state in [ExtruderModel.State.RUNNING]:
			break
		if m.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE, ExtruderModel.State.PREHEAT]:
			m.melt_temp = maxf(m.melt_temp, m._preheat_ready_temp() + 1.0)
		if not pressed or (i % 600 == 599 and m.state in [ExtruderModel.State.OFF, ExtruderModel.State.IDLE]):
			brain._pending["start_production"] = true
			pressed = true
		await get_tree().process_frame
	print("[probe] extruder state %s after %.0f s sim, melt %.1f, alarm '%s'" % [
		ExtruderModel.State.keys()[m.state], _frames / 60.0, m.melt_temp, String(m.start_seq.alarm)])

	# 2) the line, then the bales on its head
	lf.call("start_line")
	var edges : Array = lf.get("_edges")
	var has_in := {}
	for e in edges:
		has_in[int(e["b"])] = true
	var head : Node3D = null
	for i in nodes.size():
		if String(nodes[i].get("role", "")) != "sink" and not has_in.has(i) and is_instance_valid(nodes[i].get("node")):
			head = nodes[i]["node"]; break
	print("[probe] head %s" % (String(head.get_meta("placeable_id", "?")) if head else "NONE"))
	var dropped := 0
	var t_sim := 0.0
	var next_report := 0.0
	var start_frames := _frames
	while t_sim < secs:
		t_sim = (_frames - start_frames) / 60.0
		if dropped < bales and head != null and t_sim >= 5.0 + 60.0 * dropped:
			var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
			world.add_child(bale)
			bale.global_position = lf.call("_head_feed_point", head)
			bale.set_meta("delivered", true)
			dropped += 1
			print("[probe] t=%.0f s bale %d dropped" % [t_sim, dropped])
		if t_sim >= next_report:
			next_report += 10.0
			_report(lf, m, t_sim)
		await get_tree().process_frame
	_report(lf, m, t_sim)
	print("PROBE RESULT: fed %.1f kg, banked past the weegschaal %.1f kg, estop %s, extruder %s" % [
		float(lf.get("fed_mass")), float(lf.get("gran_mass")), str(lf.get("estop_active")),
		ExtruderModel.State.keys()[m.state]])
	get_tree().quit(0)

func _report(lf: Node, m, t: float) -> void:
	var parts : PackedStringArray = []
	for nd in lf.get("_nodes"):
		var id := String(nd.get("id", ""))
		if not WATCH_IDS.has(id):
			continue
		var outb = nd.get("out")
		parts.append("%s in%.1f out%.1f%s" % [id, float(nd.get("buffer", 0.0)),
			(outb.mass_kg if outb != null else 0.0), "" if bool(nd.get("powered", false)) else " OFF"])
	print("[t=%4.0f] fed %.1f transit %.1f banked %.1f estop %s ext %s | %s" % [t,
		float(lf.get("fed_mass")), float(lf.call("in_transit_mass")), float(lf.get("gran_mass")),
		str(lf.get("estop_active")), ExtruderModel.State.keys()[m.state], " | ".join(parts)])

func _find_script(n: Node, file: String) -> Node:
	var s = n.get_script()
	if s != null and String(s.resource_path).ends_with("/" + file):
		return n
	for c in n.get_children():
		var r := _find_script(c, file)
		if r != null:
			return r
	return null
