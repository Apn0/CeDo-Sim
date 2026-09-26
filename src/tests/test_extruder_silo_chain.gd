extends Node
## The extruder silo is FED, feeds its compactorband, and the band feeds THE
## extruder — on lines 1, 3A and 3B, asserted by name and by kg.
##
##   godot --headless --path . res://src/tests/test_extruder_silo_chain.tscn
##
## WHY THIS FILE EXISTS. Measured 2026-09-25 (dump_line_graph.tscn), the tails
## of 3A and 3B were wired wrong for as long as they existed, and no suite saw it:
##   3A  extruder_silo in [blower, compactorband]  out [compactorband]
##       compactorband out [extruder_silo]           extruder_3a in []
##   3B  extruder_silo in []                       out [compactorband]
##       compactorband out [blower]  blower out [cyclone]  cyclone out [blower]
##                                                   extruder_3b in []
## 950 kg/h fed into the 3A/3B silo reached the extruder as 0 kg/h after 300 s.
## Two causes, both in LineFlow's nearest-input-port fallback, which wires any
## two consecutive MAIN SEQ entries that carry no explicit edge:
##   1. The extruder's inlet is 15.22 m (3A) / 14.24 m (3B) from the band's
##      discharge — past MAX_LINK_DIST (14 m) — so the band never even sees
##      it as a candidate and falls back to the nearest inlet behind it.
##      (Line 1's is 14.24 m too; its tail was pinned on 2026-09-24.)
##   2. The fallback's cycle guard is called with its arguments swapped
##      (`_creates_cycle(best, src)` against a `(from, to)` contract), so it
##      asks whether the SOURCE already reaches the target instead of whether
##      the target reaches the source, and never rejects a back-edge. That is
##      how compactorband → extruder_silo (3A) and blower → cyclone (3B)
##      became 2-cycles, and how the 3B silo lost its only in-edge.
## Fixed in BuildMode.LINE_3A_SEQ / LINE_3B_SEQ by pinning the chain with
## `explicit_from_prev`, the way line 1's tail was pinned on 2026-09-24.
##
## WHAT A NAIVE CHECK MISSES. On 3A the band had in-degree 1 and out-degree 1,
## and the silo had an in-edge from the right blower: every "is it connected"
## check passes on a sibling 2-cycle. So this asserts the EXACT neighbours by
## name, looks for the 2-cycle explicitly, and then moves real kg:
##   G  graph — upstream → silo → band → extruder, each edge exact, no 2-cycle
##   F  flow  — 950 kg/h into the silo's upstream for FEED_S; the kg must
##             arrive at the silo, the band and the NAMED extruder, and no node
##             of the chain may process more mass than was fed (a 2-cycle
##             circulates: on 3A the silo "moved" 6 kg/s from 0.26 kg/s fed).
##
## Production path, no mocks: BuildMode._build_full_line → LineFlow.rebuild →
## start_line → tick(0.1). All three lines stand in ONE world with ONE LineFlow,
## 400 m apart (MAX_LINK_DIST is 14 m, so they cannot cross-wire), which is how
## the plant runs them. A bare BuildMode never saves (SaveCoordinator owns the
## autosave), so nothing here writes user://.
##
## SCOPE — a line in the session it is BUILT. `lf_explicit_outs` is not
## persisted by _save_layout, and until 2026-09-25 nothing re-stamped it, so a
## reloaded world had none of these pins (probe_explicit_edges_roundtrip, 47
## tagged nodes → 0). load_layout now re-derives them from the SEQ
## (BuildMode._rederive_macro_flow_edges); the RELOADED world, these chains
## included, is test_macro_edges_reload's job, by name and by kg.

const FEED_KG_H : float = 950.0        # ExtruderConfig's 3B nominal, as the probe used
# Measured 2026-09-25 on the fixed tree: the first kg reaches the extruder
# 19.6 s (3A) / 23.8 s (1) / 27.4 s (3B) after feeding starts, ~15 s of it
# pipe transit from the feeder, so the last kg fed at 120 s is in by ~135 s.
const FEED_S    : float = 120.0        # feed window
const DRAIN_S   : float = 60.0         # then let the pipes empty
const REACH_FRAC : float = 0.5         # at least half the fed kg must arrive at each hop
const CIRC_FRAC  : float = 1.05        # no hop may process more than fed (+5 % slack)
const WATCHDOG_MS : int = 300000

# line → the SEQ entry that must feed its silo, and its extruder. Origins are
# far apart so the three lines share one LineFlow without touching.
const LINES : Array = [
	{"line": "line_1",  "upstream": "cyclone", "extruder": "extruder_1",  "origin": Vector3(0.0, 0.0, 0.0)},
	{"line": "line_3a", "upstream": "blower",  "extruder": "extruder_3a", "origin": Vector3(400.0, 0.0, 0.0)},
	{"line": "line_3b", "upstream": "blower",  "extruder": "extruder_3b", "origin": Vector3(800.0, 0.0, 0.0)},
]

var _ok : int = 0
var _fails : int = 0
var _t0 : int = 0
var _done : bool = false

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_ok += 1
	else:
		_fails += 1

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

## Hang guard. The tick loop below never yields, so this only runs if `_run`
## aborted on a SCRIPT ERROR after an await — the mode where a headless suite
## otherwise idles forever with no verdict (CLAUDE.md, 2026-09-22 trap).
func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		print("Result: FAIL (watchdog — no verdict after %d s)" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

func _seq_of(line_id: String) -> Array:
	match line_id:
		"line_1":  return BuildMode.LINE_1_SEQ
		"line_3a": return BuildMode.LINE_3A_SEQ
		"line_3b": return BuildMode.LINE_3B_SEQ
	return []

func _seq_index(seq: Array, id: String, from: int = 0) -> int:
	for k in range(from, seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			return k
	return -1

## LineFlow node index of (macro_id, macro_index), or -1.
func _node_at(nodes: Array, line_id: String, mi: int) -> int:
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3):
			continue
		if String(n3.get_meta("macro_id", "")) == line_id and int(n3.get_meta("macro_index", -1)) == mi:
			return i
	return -1

func _label(nodes: Array, i: int) -> String:
	return "%s#%d" % [String((nodes[i] as Dictionary).get("id", "?")), i] if i >= 0 else "<none>"

func _names(nodes: Array, idxs: Array) -> String:
	var out : Array = []
	for j in idxs:
		out.append(_label(nodes, int(j)))
	return "[" + ", ".join(out) + "]"

func _run() -> void:
	print("[TEST] extruder silo chain — upstream → extruder_silo → compactorband → extruder, lines 1/3A/3B")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	for spec in LINES:
		bm.call("_build_full_line", String(spec["line"]), spec["origin"] as Vector3, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var outs : Dictionary = {}
	var ins : Dictionary = {}
	for e in edges:
		var a : int = int((e as Dictionary)["a"])
		var b : int = int((e as Dictionary)["b"])
		outs[a] = (outs.get(a, []) as Array) + [b]
		ins[b] = (ins.get(b, []) as Array) + [a]

	# ── G — the wired graph, per line, by name ───────────────────────────────
	var chains : Array = []     # [{line, up, silo, band, ex}] of LineFlow indices
	for spec in LINES:
		var line_id : String = spec["line"]
		var seq : Array = _seq_of(line_id)
		var mi_silo : int = _seq_index(seq, "extruder_silo")
		var mi_band : int = _seq_index(seq, "compactorband", maxi(mi_silo, 0))
		var mi_ex : int = _seq_index(seq, String(spec["extruder"]))
		print("  -- G %s --" % line_id)
		# The silo's feeder is the SEQ entry right before it, and it must be the
		# machine the plant docs name (3A ruling 2.1-B: M11b's blower; 3B ruling
		# 3.1-B: the tussenventilator's booster blower; line 1: the tail cyclone).
		var up_id : String = String((seq[mi_silo - 1] as Dictionary).get("id", "")) if mi_silo > 0 else ""
		_check(mi_silo > 0 and up_id == String(spec["upstream"]),
			"G0 %s: the entry before extruder_silo is '%s' (got '%s')" % [line_id, spec["upstream"], up_id])
		_check(mi_band == mi_silo + 1 and mi_ex == mi_band + 1,
			"G0 %s: SEQ runs extruder_silo(%d) → compactorband(%d) → %s(%d)"
			% [line_id, mi_silo, mi_band, spec["extruder"], mi_ex])
		var up : int = _node_at(nodes, line_id, mi_silo - 1)
		var silo : int = _node_at(nodes, line_id, mi_silo)
		var band : int = _node_at(nodes, line_id, mi_band)
		var ex : int = _node_at(nodes, line_id, mi_ex)
		var resolved : bool = up >= 0 and silo >= 0 and band >= 0 and ex >= 0
		_check(resolved, "G0 %s: all four chain machines are LineFlow nodes (%s %s %s %s)"
			% [line_id, _label(nodes, up), _label(nodes, silo), _label(nodes, band), _label(nodes, ex)])
		if not resolved:
			continue
		chains.append({"line": line_id, "up": up, "silo": silo, "band": band, "ex": ex,
			"ex_id": String(spec["extruder"])})
		var up_out : Array = outs.get(up, [])
		var silo_in : Array = ins.get(silo, [])
		var silo_out : Array = outs.get(silo, [])
		var band_out : Array = outs.get(band, [])
		var ex_in : Array = ins.get(ex, [])
		_check(up_out == [silo], "G1 %s: %s feeds ONLY the silo — out %s"
			% [line_id, _label(nodes, up), _names(nodes, up_out)])
		_check(silo_in == [up], "G2 %s: the silo is fed ONLY by %s — in %s"
			% [line_id, _label(nodes, up), _names(nodes, silo_in)])
		_check(silo_out == [band], "G3 %s: the silo feeds ONLY its compactorband — out %s"
			% [line_id, _names(nodes, silo_out)])
		_check(band_out == [ex], "G4 %s: the compactorband feeds ONLY %s — out %s"
			% [line_id, spec["extruder"], _names(nodes, band_out)])
		_check(ex_in == [band], "G5 %s: %s is fed ONLY by the compactorband — in %s"
			% [line_id, spec["extruder"], _names(nodes, ex_in)])
		# The sibling 2-cycle, looked for by name: a pair that feeds each other
		# passes every in/out-degree check, so name it if it exists.
		var cyc : Array = []
		for x in [up, silo, band, ex]:
			for y in outs.get(x, []):
				if (outs.get(int(y), []) as Array).has(x):
					var tag := "%s <-> %s" % [_label(nodes, mini(x, int(y))), _label(nodes, maxi(x, int(y)))]
					if not cyc.has(tag):
						cyc.append(tag)
		_check(cyc.is_empty(), "G6 %s: no 2-cycle on the silo chain %s"
			% [line_id, str(cyc) if not cyc.is_empty() else "(none)"])

	_check(chains.size() == LINES.size(),
		"G7 all %d lines resolved a chain to measure (anti-vacuity)" % LINES.size())

	# ── F — real kg, fed at the silo's feeder, followed to the named extruder ─
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var moved : Dictionary = {}          # node idx → Σ _moved_kg
	for ch in chains:
		for key in ["up", "silo", "band", "ex"]:
			moved[int(ch[key])] = 0.0
	var fed : float = 0.0
	var feed_ticks : int = int(FEED_S / 0.1)
	var total_ticks : int = int((FEED_S + DRAIN_S) / 0.1)
	var first_t : Dictionary = {}        # node idx → sim s it first processed kg
	var t_wall : int = Time.get_ticks_msec()
	for t in total_ticks:
		if t < feed_ticks:
			for ch in chains:
				(((nodes[int(ch["up"])] as Dictionary)["in"]) as MaterialBatch).add(MaterialBatch.new(
					feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
					LineFlow.DEFAULT_COMP.duplicate(), "silo_chain", 0.0, 0.0))
			fed += feed_kg_tick
		lf.call("tick", 0.1)
		for i in moved.keys():
			var m : float = float((nodes[int(i)] as Dictionary).get("_moved_kg", 0.0))
			moved[i] = float(moved[i]) + m
			if m > 0.0 and not first_t.has(i):
				first_t[i] = float(t + 1) * 0.1
	print("  info  : %d ticks (%.0f s sim) in %.1f s wall; fed %.1f kg into each line's silo feeder"
		% [total_ticks, (FEED_S + DRAIN_S), (Time.get_ticks_msec() - t_wall) / 1000.0, fed])
	_check(fed > 0.0, "F0 kg were fed (%.1f kg per line)" % fed)

	for ch in chains:
		var line_id : String = ch["line"]
		print("  -- F %s --" % line_id)
		# Received = what the node processed + what is still in its input buffer.
		var got : Dictionary = {}
		for key in ["up", "silo", "band", "ex"]:
			var i : int = int(ch[key])
			var bin : MaterialBatch = (nodes[i] as Dictionary).get("in", null) as MaterialBatch
			got[key] = float(moved[i]) + (bin.mass_kg if bin != null else 0.0)
			print("  info  : %-22s processed %8.1f kg, received %8.1f kg, first kg at %s"
				% [_label(nodes, i), float(moved[i]), float(got[key]),
				("%.1f s" % float(first_t[i])) if first_t.has(i) else "never"])
		_check(float(got["silo"]) >= REACH_FRAC * fed,
			"F1 %s: the fed kg reach the extruder_silo (%.1f of %.1f kg)" % [line_id, float(got["silo"]), fed])
		_check(float(got["band"]) >= REACH_FRAC * fed,
			"F2 %s: the kg reach the compactorband (%.1f of %.1f kg)" % [line_id, float(got["band"]), fed])
		_check(float(got["ex"]) >= REACH_FRAC * fed,
			"F3 %s: the kg reach %s by name (%.1f of %.1f kg)" % [line_id, ch["ex_id"], float(got["ex"]), fed])
		var worst : String = ""
		var worst_kg : float = 0.0
		for key in ["up", "silo", "band", "ex"]:
			var i : int = int(ch[key])
			if float(moved[i]) > worst_kg:
				worst_kg = float(moved[i])
				worst = _label(nodes, i)
		_check(worst_kg <= CIRC_FRAC * fed,
			"F4 %s: no chain machine processes more than was fed — nothing circulates (max %s %.1f kg, fed %.1f)"
			% [line_id, worst, worst_kg, fed])
	_finish()

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] extruder silo chain %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
