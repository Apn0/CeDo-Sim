extends Node
## LineFlow's geometry fallback wires NO cycle on any macro line, keeps the
## fixtures out of the flow graph, and the chains the fixed cycle guard
## rerouted are the plant's — asserted by name and by kg.
##
##   godot --headless --path . res://src/tests/test_fallback_chains.tscn
##
## WHY THIS FILE EXISTS. Measured 2026-09-25 with dump_line_graph.tscn on all
## seven macros: LineFlow._link_best_target called `_creates_cycle(best, src)`
## against a `(from, to)` contract, so it asked whether the SOURCE already
## reached the target — never true in the geometry pass — and #78's cycle guard
## never refused a single back-edge. 36 edges sat on cycles (on main + #289):
##   3A        wind_sifter <-> infeed blower 2; the big top cyclone had NO
##             in-edge, so nothing from the mech dryer reached the mengsilo
##   1, 3B     centrifuge <-> weegschaal; voorraad_silo had NO in-edge
##   1/3A/3B/3C lump_cart <-> lump_cart_spot (furniture as flow nodes)
##   every line with air users: compressor_a <-> compressor_b
##   intakes / sort: switch_belt, inclined belt and trilzeef back-edges
## Swapping the arguments removes every cycle, but a refused candidate falls
## through to the NEXT one, and three of those were wrong too: every lump cart
## then fed the laser filter (vacuum_degas on 3C), and 3A's blower 2 fed
## doseerschroef M11b — the infeed skipping the mengsilo. Settled per edge:
##   * swap alone right:  weegschaal → voorraad_silo on 1 and 3B (doc edges
##                        lijn_1 39 / lijn_3b 27)
##   * pin needed:        3A blower 2 → big top cyclone (ruling 2.1-B),
##                        `explicit_from_prev` on the cyclone entry
##   * not a flow node:   lump_platform / lump_cart_spot / lump_cart /
##                        compressor_a / compressor_b → MachineFlow role
##                        "none", which three code comments already claimed
## docs/audit/cycle_guard_swap_2026-09-25.md has the before/after edge diffs.
##
## WHAT A NAIVE CHECK MISSES. A sibling 2-cycle passes every in/out-degree
## check, and a missing in-edge only shows as a node that is suddenly a feed
## HEAD (LineFlow draws a bale into any non-sink with no in-edge). So this
## asserts, on ONE world holding all seven macros 400 m apart:
##   C  no cycle of ANY length among non-recirc edges, per line
##   X  the five fixture ids ARE in the world and are NOT LineFlow nodes
##   H  lines 1/3A/3B/3C: the only non-sink nodes with no in-edge are the
##      plant's own feed heads, and no non-sink dead-ends
##   G  each chain edge exact by name, plus an explicit 2-cycle search
##   F  950 kg/h fed at each chain's first machine for FEED_S: the kg must
##      reach its last machine by name, and no chain machine may process more
##      than was fed (a cycle circulates mass)
##
## Production path, no mocks: BuildMode._build_full_line → LineFlow.rebuild →
## start_line → tick(0.1). A bare BuildMode never saves, so nothing here
## writes user://.
##
## SCOPE — a line in the session it is BUILT. BuildMode does not persist
## lf_explicit_outs, so a reloaded world loses the 3A cyclone pin (and every
## other explicit edge); that is extruder_silo_tail_2026-09-25.md §7, its own
## defect. The C, X and H claims that do not rest on a pin hold after a reload
## too — measured with `dump_line_graph.tscn -- <line> --reload`, not asserted.

const FEED_KG_H  : float = 950.0
const FEED_S     : float = 120.0
const DRAIN_S    : float = 60.0
const REACH_FRAC : float = 0.5
# Not 1.05 (the silo-chain suite's bound): the heetafslag adds process water,
# so on the granulate chains the ontwaterzeef handles 33.3 kg and the
# centrifuge 32.0 kg for 31.7 kg fed (measured 2026-09-25, +5.0 % / +1.0 %).
# A cycle circulates far past that — see the mutation table in the audit doc.
const CIRC_FRAC  : float = 1.25
const WATCHDOG_MS : int = 360000

const LINES : Array = [
	{"line": "line_1",           "origin": Vector3(0.0,    0.0, 0.0)},
	{"line": "line_3a",          "origin": Vector3(400.0,  0.0, 0.0)},
	{"line": "line_3b",          "origin": Vector3(800.0,  0.0, 0.0)},
	{"line": "line_3c",          "origin": Vector3(1200.0, 0.0, 0.0)},
	{"line": "line_intake_3a3b", "origin": Vector3(1600.0, 0.0, 0.0)},
	{"line": "line_sort",        "origin": Vector3(2000.0, 0.0, 0.0)},
	{"line": "line_intake_3c6",  "origin": Vector3(2400.0, 0.0, 0.0)},
]

const FIXTURE_IDS : Array = ["lump_platform", "lump_cart_spot", "lump_cart", "compressor_a", "compressor_b"]

# H — the plant's own feed heads. The wash lines start at the VSS and the
# vuilsnippersilo (both filled from outside the macro), line 1 at its opzetband,
# 3C at its doseersilo. Sort / intake macros are left out on purpose. Their
# belts used to be discovered twice, which made every twin a head; that is
# fixed (test_flow_node_unique). What is left is still not the plant: the
# opzetband bypasses shredder 2 (intake) / shredder 1 (sort), and both
# shredders are heads (docs/audit/flow_node_twins_2026-09-25.md §6).
const HEADS : Dictionary = {
	"line_1":  ["opzetband_1"],
	"line_3a": ["vss_silo", "vuilsnippersilo"],
	"line_3b": ["vss_silo", "vuilsnippersilo"],
	"line_3c": ["doseersilo"],
}

# G/F — the chains the fixed guard rerouted. `after` anchors the search in the
# SEQ; `path` is walked in order from there. `feeder` is the machine that must
# feed path[0] alone. `open_end` = the last machine may have other inputs too
# (the mengsilo also takes the ring's recirc).
const CHAINS : Array = [
	{"name": "3A infeed (ruling 2.1-B)", "line": "line_3a", "after": "mech_dryer",
	 "feeder": "mech_dryer",
	 "path": ["blower", "wind_sifter", "blower", "cyclone", "mengsilo"], "open_end": true},
	{"name": "line 1 granulate", "line": "line_1", "after": "extruder_1",
	 "feeder": "extruder_1",
	 "path": ["laser_filter", "heetafslag", "ontwaterzeef", "centrifuge", "weegschaal", "voorraad_silo"],
	 "open_end": false},
	{"name": "3B granulate", "line": "line_3b", "after": "extruder_3b",
	 "feeder": "extruder_3b",
	 "path": ["laser_filter", "heetafslag", "ontwaterzeef", "centrifuge", "weegschaal", "voorraad_silo"],
	 "open_end": false},
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

## Hang guard: only fires if `_run` aborted on a SCRIPT ERROR after an await,
## the mode where a headless suite idles forever with no verdict.
func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		print("Result: FAIL (watchdog — no verdict after %d s)" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

func _seq_of(line_id: String) -> Array:
	match line_id:
		"line_1":           return BuildMode.LINE_1_SEQ
		"line_3a":          return BuildMode.LINE_3A_SEQ
		"line_3b":          return BuildMode.LINE_3B_SEQ
		"line_3c":          return BuildMode.LINE_3C_SEQ
		"line_intake_3a3b": return BuildMode.INTAKE_3A3B_SEQ
		"line_sort":        return BuildMode.LINE_SORT_SEQ
		"line_intake_3c6":  return BuildMode.LINE_3C6_SEQ
	return []

## Next MAIN (x == 0) entry with this id at or after `from`, or -1. Side-lane
## entries share ids with the main path (3A's recirc screw and blower), so only
## the main centreline is searched.
func _main_index(seq: Array, id: String, from: int) -> int:
	for k in range(maxi(from, 0), seq.size()):
		var e : Dictionary = seq[k]
		if String(e.get("id", "")) == id and is_equal_approx(float(e.get("x", 0.0)), 0.0):
			return k
	return -1

## Next entry with this id at or after `from` (main or side lane), or -1.
func _any_index(seq: Array, id: String, from: int) -> int:
	for k in range(maxi(from, 0), seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			return k
	return -1

func _line_of(nd: Dictionary) -> String:
	var n3 = nd.get("node")
	if n3 == null or not is_instance_valid(n3):
		return ""
	return String(n3.get_meta("macro_id", ""))

func _node_at(nodes: Array, line_id: String, mi: int) -> int:
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3):
			continue
		if String(n3.get_meta("macro_id", "")) == line_id and int(n3.get_meta("macro_index", -1)) == mi:
			return i
	return -1

func _label(nodes: Array, i: int) -> String:
	if i < 0:
		return "<none>"
	var n3 = (nodes[i] as Dictionary).get("node")
	var mi : int = int(n3.get_meta("macro_index", -1)) if n3 != null and is_instance_valid(n3) else -1
	return "%s#%d[m%d]" % [String((nodes[i] as Dictionary).get("id", "?")), i, mi]

func _names(nodes: Array, idxs: Array) -> String:
	var out : Array = []
	for j in idxs:
		out.append(_label(nodes, int(j)))
	return "[" + ", ".join(out) + "]"

func _run() -> void:
	print("[TEST] fallback chains — no cycles, no fixtures in the graph, rerouted chains by name and by kg")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	for spec in LINES:
		bm.call("_build_full_line", String(spec["line"]), spec["origin"] as Vector3, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var outs : Dictionary = {}       # every edge, recirc included
	var ins : Dictionary = {}
	var fwd : Dictionary = {}        # non-recirc only — what a cycle is made of
	for e in edges:
		var a : int = int((e as Dictionary)["a"])
		var b : int = int((e as Dictionary)["b"])
		outs[a] = (outs.get(a, []) as Array) + [b]
		ins[b] = (ins.get(b, []) as Array) + [a]
		if not bool((e as Dictionary).get("recirc", false)):
			fwd[a] = (fwd.get(a, []) as Array) + [b]
	print("  info  : %d LineFlow nodes, %d edges across %d macros" % [nodes.size(), edges.size(), LINES.size()])

	# ── C — no cycle of any length, per line ─────────────────────────────────
	# An edge a → b sits on a cycle iff b already reaches a. Cross-line edges
	# cannot exist (400 m apart, MAX_LINK_DIST 14 m) and are counted here too.
	print("  -- C: cycles --")
	var per_line_nodes : Dictionary = {}
	for i in nodes.size():
		var lid : String = _line_of(nodes[i])
		per_line_nodes[lid] = int(per_line_nodes.get(lid, 0)) + 1
	var cyc_by_line : Dictionary = {}
	for a in fwd.keys():
		for b in fwd[a]:
			var seen : Dictionary = {}
			var stack : Array = [int(b)]
			var hit := false
			while not stack.is_empty():
				var cur : int = int(stack.pop_back())
				if cur == int(a):
					hit = true
					break
				if seen.has(cur):
					continue
				seen[cur] = true
				for nx in fwd.get(cur, []):
					stack.append(int(nx))
			if hit:
				var lid : String = _line_of(nodes[int(a)])
				cyc_by_line[lid] = (cyc_by_line.get(lid, []) as Array) + ["%s -> %s" % [_label(nodes, int(a)), _label(nodes, int(b))]]
	for spec in LINES:
		var lid : String = spec["line"]
		var n_line : int = int(per_line_nodes.get(lid, 0))
		_check(n_line > 0, "C0 %s: the macro built LineFlow nodes (%d)" % [lid, n_line])
		var c : Array = cyc_by_line.get(lid, [])
		_check(c.is_empty(), "C1 %s: no non-recirc edge sits on a cycle %s"
			% [lid, str(c) if not c.is_empty() else "(0)"])
	var stray : Array = cyc_by_line.get("", [])
	_check(stray.is_empty(), "C2 no cycle through a node outside the macros %s"
		% (str(stray) if not stray.is_empty() else "(0)"))

	# ── X — the fixtures are placed, and are not flow nodes ──────────────────
	print("  -- X: fixtures --")
	var placed : Dictionary = {}
	for po in get_tree().get_nodes_in_group("placed_object"):
		if po is Node3D and po.has_meta("placeable_id"):
			var pid : String = String(po.get_meta("placeable_id"))
			if FIXTURE_IDS.has(pid):
				placed[pid] = int(placed.get(pid, 0)) + 1
	var in_graph : Dictionary = {}
	for nd in nodes:
		var nid : String = String((nd as Dictionary).get("id", ""))
		if FIXTURE_IDS.has(nid):
			in_graph[nid] = int(in_graph.get(nid, 0)) + 1
	for fid in FIXTURE_IDS:
		# Anti-vacuity: a fixture that was never placed is trivially absent.
		_check(int(placed.get(fid, 0)) > 0, "X0 %s is in the world (%d placed)" % [fid, int(placed.get(fid, 0))])
		_check(int(in_graph.get(fid, 0)) == 0, "X1 %s is NOT a LineFlow node (%d found)" % [fid, int(in_graph.get(fid, 0))])
		_check(String(MachineFlow.profile(fid).get("role", "")) == "none",
			"X2 MachineFlow.profile('%s').role == \"none\"" % fid)

	# ── H — feed heads and dead ends on the four process lines ───────────────
	print("  -- H: heads and dead ends --")
	for lid in HEADS.keys():
		var heads : Array = []
		var dead : Array = []
		for i in nodes.size():
			if _line_of(nodes[i]) != lid or String((nodes[i] as Dictionary).get("role", "")) == "sink":
				continue
			if (ins.get(i, []) as Array).is_empty():
				heads.append(String((nodes[i] as Dictionary).get("id", "")))
			if (outs.get(i, []) as Array).is_empty():
				dead.append(_label(nodes, i))
		heads.sort()
		var want : Array = (HEADS[lid] as Array).duplicate()
		want.sort()
		_check(heads == want, "H1 %s: the only non-sink nodes with no in-edge are %s (got %s)" % [lid, str(want), str(heads)])
		_check(dead.is_empty(), "H2 %s: no non-sink node dead-ends %s" % [lid, str(dead) if not dead.is_empty() else "(0)"])

	# ── G — the rerouted chains, edge by edge ────────────────────────────────
	var runs : Array = []      # [{name, line, idx: Array[int]}] for F
	for ch in CHAINS:
		var lid : String = ch["line"]
		var seq : Array = _seq_of(lid)
		print("  -- G %s --" % ch["name"])
		var mi_after : int = _main_index(seq, String(ch["after"]), 0)
		var mis : Array = []
		var cursor : int = mi_after + 1
		for pid in ch["path"]:
			# The laser filter stands on the side lane beside its extruder;
			# everything else on these chains is main-line.
			var k : int = _any_index(seq, String(pid), cursor) if String(pid) == "laser_filter" \
				else _main_index(seq, String(pid), cursor)
			mis.append(k)
			cursor = k + 1 if k >= 0 else seq.size()
		var idx : Array = []
		for k in mis:
			idx.append(_node_at(nodes, lid, int(k)) if int(k) >= 0 else -1)
		var feeder : int = _node_at(nodes, lid, mi_after)
		var resolved : bool = mi_after >= 0 and feeder >= 0 and not idx.has(-1)
		_check(resolved, "G0 %s: every chain machine is a LineFlow node %s (SEQ %s)"
			% [ch["name"], _names(nodes, idx), str(mis)])
		if not resolved:
			continue
		# The first machine is fed by the feeder alone.
		_check(ins.get(int(idx[0]), []) == [feeder], "G1 %s: %s is fed ONLY by %s — in %s"
			% [ch["name"], _label(nodes, int(idx[0])), _label(nodes, feeder), _names(nodes, ins.get(int(idx[0]), []))])
		for k in range(idx.size() - 1):
			var a : int = int(idx[k])
			var b : int = int(idx[k + 1])
			_check(outs.get(a, []) == [b], "G2 %s: %s feeds ONLY %s — out %s"
				% [ch["name"], _label(nodes, a), _label(nodes, b), _names(nodes, outs.get(a, []))])
			var last : bool = k + 1 == idx.size() - 1
			if last and bool(ch["open_end"]):
				_check((ins.get(b, []) as Array).has(a), "G3 %s: %s is fed by %s — in %s"
					% [ch["name"], _label(nodes, b), _label(nodes, a), _names(nodes, ins.get(b, []))])
			else:
				_check(ins.get(b, []) == [a], "G3 %s: %s is fed ONLY by %s — in %s"
					% [ch["name"], _label(nodes, b), _label(nodes, a), _names(nodes, ins.get(b, []))])
		# The sibling 2-cycle, by name — it passes every degree check.
		var cyc : Array = []
		for x in [feeder] + idx:
			for y in outs.get(int(x), []):
				if (outs.get(int(y), []) as Array).has(int(x)):
					var tag := "%s <-> %s" % [_label(nodes, mini(int(x), int(y))), _label(nodes, maxi(int(x), int(y)))]
					if not cyc.has(tag):
						cyc.append(tag)
		_check(cyc.is_empty(), "G4 %s: no 2-cycle on the chain %s" % [ch["name"], str(cyc) if not cyc.is_empty() else "(none)"])
		runs.append({"name": ch["name"], "line": lid, "idx": idx, "open_end": bool(ch["open_end"])})
	_check(runs.size() == CHAINS.size(), "G5 all %d chains resolved to measure (anti-vacuity)" % CHAINS.size())

	# ── F — real kg along each chain ─────────────────────────────────────────
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var moved : Dictionary = {}
	for r in runs:
		for i in r["idx"]:
			moved[int(i)] = 0.0
	var first_t : Dictionary = {}
	var fed : float = 0.0
	var feed_ticks : int = int(FEED_S / 0.1)
	var total_ticks : int = int((FEED_S + DRAIN_S) / 0.1)
	var t_wall : int = Time.get_ticks_msec()
	for t in total_ticks:
		if t < feed_ticks:
			for r in runs:
				(((nodes[int((r["idx"] as Array)[0])] as Dictionary)["in"]) as MaterialBatch).add(MaterialBatch.new(
					feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
					LineFlow.DEFAULT_COMP.duplicate(), "fallback_chain", 0.0, 0.0))
			fed += feed_kg_tick
		lf.call("tick", 0.1)
		for i in moved.keys():
			var m : float = float((nodes[int(i)] as Dictionary).get("_moved_kg", 0.0))
			moved[i] = float(moved[i]) + m
			if m > 0.0 and not first_t.has(i):
				first_t[i] = float(t + 1) * 0.1
	print("  info  : %d ticks (%.0f s sim) in %.1f s wall; fed %.1f kg at each chain's first machine"
		% [total_ticks, FEED_S + DRAIN_S, (Time.get_ticks_msec() - t_wall) / 1000.0, fed])
	_check(fed > 0.0, "F0 kg were fed (%.1f kg per chain)" % fed)
	for r in runs:
		print("  -- F %s --" % r["name"])
		var idx : Array = r["idx"]
		for i in idx:
			var bin : MaterialBatch = (nodes[int(i)] as Dictionary).get("in", null) as MaterialBatch
			print("  info  : %-28s processed %8.1f kg, buffered %7.1f kg, first kg at %s"
				% [_label(nodes, int(i)), float(moved[int(i)]), bin.mass_kg if bin != null else 0.0,
				("%.1f s" % float(first_t[int(i)])) if first_t.has(int(i)) else "never"])
		var last : int = int(idx[idx.size() - 1])
		var lbin : MaterialBatch = (nodes[last] as Dictionary).get("in", null) as MaterialBatch
		var got : float = float(moved[last]) + (lbin.mass_kg if lbin != null else 0.0)
		_check(got >= REACH_FRAC * fed, "F1 %s: the fed kg reach %s by name (%.1f of %.1f kg)"
			% [r["name"], _label(nodes, last), got, fed])
		# Circulation: every machine but an open-ended last one (the mengsilo's
		# own rondmeng loop legitimately re-processes its contents).
		var worst : String = ""
		var worst_kg : float = 0.0
		for k in idx.size():
			if k == idx.size() - 1 and bool(r["open_end"]):
				continue
			var i : int = int(idx[k])
			if float(moved[i]) > worst_kg:
				worst_kg = float(moved[i])
				worst = _label(nodes, i)
		_check(worst_kg <= CIRC_FRAC * fed,
			"F2 %s: no chain machine processes more than was fed — nothing circulates (max %s %.1f kg, fed %.1f)"
			% [r["name"], worst, worst_kg, fed])
	_finish()

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] fallback chains %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
