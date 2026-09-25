extends Node
## PROBE (measures, gates nothing) — what LineFlow's ExtruderScrew publishes as
## `die_pressure` on a real macro-built line, and what that does to the MFI
## proxy, the QA spec and the Quality terminal's die-plate row ("Spuitkop-druk" until 2026-09-24).
##
##   godot --headless --path . res://src/tests/probe_screw_die_pressure.tscn -- line_3b [kg_h] [silo]
##
## Production path, no mocks: BuildMode._build_full_line → LineFlow.rebuild →
## start_line → tick(0.1). The extruder node is fed straight into its input
## buffer at `kg_h` (default 950, ExtruderConfig's 3B nominal) so the screw sees
## a steady nominal throughput without waiting for a bale to cross the plant.
## Every node that LineFlow gave an ExtruderScrew is reported, not only the
## real extruder (before 2026-09-24 `_is_extruder()` also caught extruder_silo).
## Writes nothing to user://.

const QaSpecScript := preload("res://src/sim/QaSpec.gd")
const TerminalScript := preload("res://src/scenes/hud/QualityAnalysisTerminal.gd")

const SETTLE_S : float = 300.0

var _t0 : int = 0

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

func _physics_process(_d: float) -> void:
	if Time.get_ticks_msec() - _t0 > 240000:
		print("Result: FAIL (probe watchdog — 240 s)")
		get_tree().quit(2)

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var line_id : String = args[0] if args.size() > 0 else "line_3b"
	var kg_h : float = float(args[1]) if args.size() > 1 else 950.0
	print("[PROBE] screw die_pressure on %s, extruder fed at %.0f kg/h" % [line_id, kg_h])

	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", line_id, Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")

	var nodes : Array = lf.get("_nodes")
	var ex_nodes : Array = []
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if nd.get("ex") != null:
			ex_nodes.append(i)
			print("  screw-model node #%d  id=%s  key=%s  role=%s  rate=%.1f kg/s"
				% [i, nd.get("id"), nd.get("key", ""), nd.get("role"), float(nd.get("rate", 0.0))])
	if ex_nodes.is_empty():
		print("Result: FAIL (no ExtruderScrew on %s)" % line_id)
		get_tree().quit(1)
		return

	# The extruder_silo's edges: what feeds it and what it feeds.
	var edges : Array = lf.get("_edges")
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id")) != "extruder_silo":
			continue
		var ins : Array = []
		var outs : Array = []
		for e in edges:
			if int(e["b"]) == i:
				ins.append("%s#%d" % [(nodes[int(e["a"])] as Dictionary).get("id"), int(e["a"])])
			if int(e["a"]) == i:
				outs.append("%s#%d" % [(nodes[int(e["b"])] as Dictionary).get("id"), int(e["b"])])
		print("  extruder_silo #%d  in-edges %s  out-edges %s" % [i, str(ins), str(outs)])
	# Feed ONE node: the first real extruder by default, or with a third arg
	# "silo" the extruder_silo, so its outflow reaches the extruder the way it
	# would on a running line.
	var via_silo : bool = args.size() > 2 and args[2] == "silo"
	var feed_i : int = -1
	for i in nodes.size():
		var fid := String((nodes[i] as Dictionary).get("id"))
		if (via_silo and fid == "extruder_silo") or (not via_silo and ex_nodes.has(i)):
			feed_i = i
			break
	print("  feeding node #%d (%s)" % [feed_i, (nodes[feed_i] as Dictionary).get("id") if feed_i >= 0 else "none"])
	var feed_kg_s : float = kg_h / 3600.0
	var steps : int = int(SETTLE_S / 0.1)
	for _s in steps:
		if feed_i >= 0:
			var m : float = feed_kg_s * 0.1
			((nodes[feed_i] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(m,
				m / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		lf.call("tick", 0.1)

	var spec = QaSpecScript.new()
	for i in ex_nodes:
		var nd : Dictionary = nodes[i]
		var ex = nd.get("ex")
		var mfi_v : float = float(nd.get("mfi_value", 0.0))
		print("  after %.0f s  #%d %-15s rpm_pct %.2f  screw %.0f rpm  thru %.4f kg/s (%.0f kg/h)  melt %.1f C  eta %.0f Pa.s"
			% [SETTLE_S, i, nd.get("id"), float(nd.get("rpm_pct", 1.0)), float(ex.get("screw_rpm")),
			float(nd.get("thru", 0.0)), float(nd.get("thru", 0.0)) * 3600.0,
			float(nd.get("melt_temp", 0.0)), float(nd.get("viscosity", 0.0))])
		print("      die_pressure %.4f bar   mfi_value %.1f g/10min   QaSpec.check_mfi -> %d (0 ACCEPT)"
			% [float(nd.get("die_pressure", 0.0)), mfi_v, spec.check_mfi(mfi_v)])

	var term = TerminalScript.new()
	var first : Dictionary = term.call("_first_extruder_node", lf)
	print("  Quality terminal reads node id=%s" % first.get("id", "<none>"))
	print("    MFI-proxy (g/10min) = %s" % term.call("_fmt_metric", lf, "mfi_value", " g/10min"))
	print("    Smelttemperatuur    = %s" % term.call("_fmt_metric", lf, "melt_temp", " °C"))
	print("    Matrijsdruk         = %s" % term.call("_fmt_metric", lf, "die_pressure", " bar"))
	print("    Doorzet (kg/s)      = %s" % term.call("_fmt_metric", lf, "thru", " kg/s"))
	term.free()
	var first_lf : Dictionary = lf.call("_first_extruder_node")
	print("  LineFlow SCADA reads node id=%s  (mfi %.1f, melt %.1f)"
		% [first_lf.get("id", "<none>"), float(first_lf.get("mfi_value", 0.0)), float(first_lf.get("melt_temp", 0.0))])
	print("Result: PROBE DONE")
	get_tree().quit(0)
