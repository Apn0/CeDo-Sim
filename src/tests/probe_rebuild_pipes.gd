extends Node
## PROBE — what a LineFlow.rebuild() does to the kg riding the connectors.
##
##   godot --headless --path . res://src/tests/probe_rebuild_pipes.tscn
##
## A real 3B line (BuildMode._build_full_line -> LineFlow.rebuild -> start_line),
## 950 kg/h fed at the VSS and 20 kg put into the extruder silo's input, 60 s of
## tick(0.1) (LineFlow's own _process off); then pipe_mass / in_transit / ledger
## (+ what was injected) are read,
## rebuild() is called with nothing changed, and they are read again. Then the
## compactorband is deleted the way BuildMode deletes (out of placed_object,
## removed, queue_free) and the same is read across that rebuild. Prints only;
## no verdict. A bare BuildMode never saves; nothing here writes user://.

const DT : float = 0.1
const WATCHDOG_S : float = 240.0
const FEED_KG_H : float = 950.0
const RUN_S : float = 60.0
const SILO_KG : float = 20.0

var _lf : Node = null
var _done : bool = false


func _ready() -> void:
	print("=== PROBE: kg in the connectors across LineFlow.rebuild() ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame
	await _run()
	_done = true
	print("PROBE DONE")
	get_tree().quit(0)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("PROBE WATCHDOG — no end after %.0f s" % WATCHDOG_S)
	get_tree().quit(2)


func _at(macro: String, idx: int) -> Node3D:
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(b.get_meta("macro_id", "")) == macro and int(b.get_meta("macro_index", -1)) == idx:
			return b
	return null


func _seq_idx(seq: Array, id: String, from: int = 0) -> int:
	for k in range(from, seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			return k
	return -1


func _edge_rows() -> Array:
	var rows : Array = []
	var nodes : Array = _lf.get("_nodes")
	for e in _lf.get("_edges"):
		var kg := 0.0
		for s in (e["pipe"] as Array):
			kg += (s as MaterialBatch).mass_kg
		var a : Dictionary = nodes[int(e["a"])]
		var b : Dictionary = nodes[int(e["b"])]
		rows.append("%s#%d -> %s#%d %.3f kg (stage_t %.2f / %.2f s)" % [
			String(a.get("id", "?")), int((a["node"] as Node3D).get_meta("macro_index", -1)),
			String(b.get("id", "?")), int((b["node"] as Node3D).get_meta("macro_index", -1)),
			kg, float(e["stage_t"]), float(e["stage_dt"])])
	return rows


func _read(tag: String, injected: float) -> Dictionary:
	var r := {
		"pipe": float(_lf.call("pipe_mass")),
		"transit": float(_lf.call("in_transit_mass")),
		"residual": float(_lf.call("ledger_residual")),
		"edges": (_lf.get("_edges") as Array).size(),
		"nodes": (_lf.get("_nodes") as Array).size(),
	}
	print("  %-34s nodes %d  edges %d  pipe_mass %.4f kg  in_transit %.4f kg  ledger_residual %.4f kg  (+injected %.4f = %.6f)" % [
		tag, r["nodes"], r["edges"], r["pipe"], r["transit"], r["residual"], injected,
		float(r["residual"]) + injected])
	return r


func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	var st : Node = get_node("/root/SimTick")
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)   # after add_child: READY turns it back on (only tick() moves kg)
	await get_tree().process_frame
	_lf.call("rebuild")
	var seq : Array = BuildMode.LINE_3B_SEQ
	var vss : Node3D = _at("line_3b", _seq_idx(seq, "vss_silo"))
	var silo : Node3D = _at("line_3b", _seq_idx(seq, "extruder_silo"))
	var band : Node3D = _at("line_3b", _seq_idx(seq, "compactorband"))
	print("  vss %s  extruder_silo %s  compactorband %s" % [str(vss != null), str(silo != null), str(band != null)])
	if vss == null or silo == null or band == null:
		return
	_lf.call("start_line")
	var injected := 0.0
	var b0 := MaterialBatch.new(SILO_KG, SILO_KG / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0)
	(_lf.call("node_for_body", silo)["in"] as MaterialBatch).add(b0)
	injected += SILO_KG
	var feed_tick : float = FEED_KG_H / 3600.0 * DT
	for i in int(RUN_S / DT):
		(_lf.call("node_for_body", vss)["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick,
			feed_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		injected += feed_tick
		_lf.call("tick", DT)
	print("\n[A] rebuild with nothing changed")
	var a0 := _read("before rebuild", injected)
	for row in _edge_rows():
		if row.find(" 0.000 kg") < 0:
			print("      " + row)
	_lf.call("rebuild")
	var a1 := _read("after rebuild", injected)
	for row in _edge_rows():
		if row.find(" 0.000 kg") < 0:
			print("      " + row)
	print("  LOST across the rebuild: pipe %.4f kg, ledger moved %.4f kg" % [
		float(a0["pipe"]) - float(a1["pipe"]), float(a1["residual"]) - float(a0["residual"])])
	for i in int(30.0 / DT):
		_lf.call("tick", DT)
	_read("30 s later (no feed)", injected)

	print("\n[B] delete the compactorband, then rebuild")
	for i in int(RUN_S / DT):
		(_lf.call("node_for_body", vss)["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick,
			feed_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		injected += feed_tick
		_lf.call("tick", DT)
	var bnd : Dictionary = _lf.call("node_for_body", band)
	var band_held : float = (bnd["in"] as MaterialBatch).mass_kg + (bnd["out"] as MaterialBatch).mass_kg
	var band_out_pipes := 0.0
	var into_band := 0.0
	var ni : int = (_lf.get("_nodes") as Array).find(bnd)
	for e in _lf.get("_edges"):
		var kg := 0.0
		for s in (e["pipe"] as Array):
			kg += (s as MaterialBatch).mass_kg
		if int(e["a"]) == ni:
			band_out_pipes += kg
		if int(e["b"]) == ni:
			into_band += kg
	var silo_out0 : float = (_lf.call("node_for_body", silo)["out"] as MaterialBatch).mass_kg
	var b_0 := _read("before delete+rebuild", injected)
	print("  band holds %.4f kg (in+out), %.4f kg in the pipes leaving it, %.4f kg in the pipes into it; silo out %.4f kg" % [
		band_held, band_out_pipes, into_band, silo_out0])
	band.remove_from_group("placed_object")
	band.get_parent().remove_child(band)
	band.queue_free()
	_lf.call("rebuild")
	var b_1 := _read("after delete+rebuild", injected)
	var silo_out1 : float = (_lf.call("node_for_body", silo)["out"] as MaterialBatch).mass_kg
	print("  silo out %.4f kg after (was %.4f); ledger moved %.4f kg; pipe fell %.4f kg" % [
		silo_out1, silo_out0, float(b_1["residual"]) - float(b_0["residual"]), float(b_0["pipe"]) - float(b_1["pipe"])])
