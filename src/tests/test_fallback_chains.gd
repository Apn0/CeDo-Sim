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
##   H  lines 1/3A/3B/3C and the 3A/3B intake: the only non-sink nodes with
##      no in-edge are the plant's own feed heads, and the only non-sink dead
##      ends are the ones the plant has (none, except on the intake)
##   G  each chain edge exact by name, plus an explicit 2-cycle search
##   O  the intake's conveyor 8 overflow, by name (C8's edge ORDER too) and
##      by kg with C8 forward and C8 held in reverse
##   F  950 kg/h fed at each chain's first machine (or at its feeder) for
##      FEED_S: the kg must reach its last machine by name, and no chain
##      machine may process more than was fed (a cycle circulates mass)
##
## 2026-09-25, the 3A/3B intake (Transportbanden 3A/3B,
## docs/audit/intake_3a3b_topology_2026-09-25.md). Measured before with
## dump_line_graph: the opzetband at its head fed the climb belt past
## shredder 2 (5.78 m against 6.44 m), so shredder 2 was a feed head, and the
## U-bay was one too. C8's only edge went to C8.5, which fed C9. The operator
## ruled the same day that the belt into shredder 2 is a plain conveyor with no
## bale on it, and confirmed the notes: C8 forward → C9, C8 reversed → C8.5 →
## U, and the U feeds nothing. H, the "intake head" chain (F3: every kg fed at
## the conveyor passes shredder 2) and O guard it.
##
## Production path, no mocks: BuildMode._build_full_line → LineFlow.rebuild →
## start_line → tick(0.1). A bare BuildMode never saves, so nothing here
## writes user://.
##
## SCOPE — a line in the session it is BUILT. Since #295 a reload re-derives
## every pin from the SEQ (BuildMode._rederive_macro_flow_edges), and that round
## trip is test_macro_edges_reload's to assert, not this suite's. The intake's
## pins were measured through `dump_line_graph.tscn -- <line> --reload` on
## 2026-09-25: the same edges, heads and dead ends, and C8's edge order.

const FEED_KG_H  : float = 950.0
const FEED_S     : float = 120.0
const DRAIN_S    : float = 60.0
const REACH_FRAC : float = 0.5
# Not 1.05 (the silo-chain suite's bound): the heetafslag adds process water,
# so on the granulate chains the ontwaterzeef handles 33.3 kg and the
# centrifuge 32.0 kg for 31.7 kg fed (measured 2026-09-25, +5.0 % / +1.0 %).
# A cycle circulates far past that — see the mutation table in the audit doc.
const CIRC_FRAC  : float = 1.25
# O — the conveyor 8 phases: warm-up (the PLC start), then per direction a feed
# at C8 and a drain long enough to empty C8 → C9 / C8.5 → U-bay before the next.
const O_WARM_S   : float = 30.0
const O_FEED_S   : float = 30.0
const O_DRAIN_S  : float = 30.0
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
# 3C at its doseersilo. The 3A/3B intake starts at the plain conveyor into
# shredder 2 (entry 0), which the sort line fills from outside the macro
# (operator 2026-09-25: no bale is ever placed on it). The sort line's heads
# and edges are asserted by test_sort_line_topology; the 3C/6 intake is not
# settled and is left out.
const HEADS : Dictionary = {
	"line_1":  ["opzetband_1"],
	"line_3a": ["vss_silo", "vuilsnippersilo"],
	"line_3b": ["vss_silo", "vuilsnippersilo"],
	"line_3c": ["doseersilo"],
	"line_intake_3a3b": ["transport_belt"],
}

# H2 — the plant's own dead ends, by id; every line in HEADS not named here has
# none. On the intake: the switch belt feeds VSS 3A / 3B, which stand on the
# 3A / 3B macros (400 m away here); the U-bay is the stortvak, which the Merlo
# empties and which feeds no conveyor (MachineFlow `no_outlet`).
const DEAD_ENDS : Dictionary = {
	"line_intake_3a3b": ["switch_belt", "u_bay"],
}

# G/F — the chains the fixed guard rerouted. `after` anchors the search in the
# SEQ; `path` is walked in order from there. `feeder` is the machine that must
# feed path[0] alone. `open_end` = the last machine may have other inputs too
# (the mengsilo also takes the ring's recirc). `feed_at_feeder` = F feeds the
# FEEDER, which must then feed path[0] alone too (G2), and F3 asserts that the
# fed kg pass through path[0] (the intake head: nothing may skip shredder 2).
const CHAINS : Array = [
	# Anchored on SEQ index 0, not on an id: the head's id is H1's to assert,
	# and the old SEQ (opzetband at 0) must still resolve so the kg checks can
	# show its bypass (mutation M0 in the audit doc).
	{"name": "3A/3B intake head (operator 2026-09-25)", "line": "line_intake_3a3b",
	 "after_index": 0, "feeder": "transport_belt",
	 "path": ["shredder_2", "inclined_belt_8m", "transportband_1"],
	 "open_end": false, "feed_at_feeder": true},
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
	lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
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
		var dead_ids : Array = []
		for i in nodes.size():
			if _line_of(nodes[i]) != lid or String((nodes[i] as Dictionary).get("role", "")) == "sink":
				continue
			if (ins.get(i, []) as Array).is_empty():
				heads.append(String((nodes[i] as Dictionary).get("id", "")))
			if (outs.get(i, []) as Array).is_empty():
				dead.append(_label(nodes, i))
				dead_ids.append(String((nodes[i] as Dictionary).get("id", "")))
		heads.sort()
		dead_ids.sort()
		var want : Array = (HEADS[lid] as Array).duplicate()
		want.sort()
		_check(heads == want, "H1 %s: the only non-sink nodes with no in-edge are %s (got %s)" % [lid, str(want), str(heads)])
		var want_dead : Array = (DEAD_ENDS.get(lid, []) as Array).duplicate()
		want_dead.sort()
		_check(dead_ids == want_dead, "H2 %s: the only non-sink dead ends are %s %s"
			% [lid, str(want_dead) if not want_dead.is_empty() else "(none)", str(dead) if not dead.is_empty() else "(0)"])

	# ── G — the rerouted chains, edge by edge ────────────────────────────────
	var runs : Array = []      # [{name, line, idx: Array[int]}] for F
	for ch in CHAINS:
		var lid : String = ch["line"]
		var seq : Array = _seq_of(lid)
		print("  -- G %s --" % ch["name"])
		var mi_after : int = int(ch["after_index"]) if ch.has("after_index") else _main_index(seq, String(ch["after"]), 0)
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
		var at_feeder : bool = bool(ch.get("feed_at_feeder", false))
		if at_feeder:
			# F feeds the feeder, so it must send everything to path[0]: the
			# opzetband's bypass was exactly a second (here: only) out-edge.
			_check(outs.get(feeder, []) == [int(idx[0])], "G2 %s: %s feeds ONLY %s — out %s"
				% [ch["name"], _label(nodes, feeder), _label(nodes, int(idx[0])), _names(nodes, outs.get(feeder, []))])
			# DECLARED, not guessed (the sort line's M4 lesson): a plain belt at
			# entry 0 may reach shredder 2 by geometry today, and a lost pin
			# would then pass every check above until the layout moves.
			var walk : Array = [feeder] + idx
			var undeclared : Array = []
			for k in range(walk.size() - 1):
				if not _declared(nodes, int(walk[k]), int(walk[k + 1])):
					undeclared.append("%s -> %s" % [_label(nodes, int(walk[k])), _label(nodes, int(walk[k + 1]))])
			_check(undeclared.is_empty(), "G6 %s: every chain edge is declared by the SEQ (lf_explicit_outs) %s"
				% [ch["name"], str(undeclared) if not undeclared.is_empty() else "(all %d)" % (walk.size() - 1)])
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
		runs.append({"name": ch["name"], "line": lid, "idx": ([feeder] + idx) if at_feeder else idx,
			"open_end": bool(ch["open_end"]), "through": int(idx[0]) if at_feeder else -1})
	_check(runs.size() == CHAINS.size(), "G5 all %d chains resolved to measure (anti-vacuity)" % CHAINS.size())

	# ── O — the intake's conveyor 8 overflow (operator's notes, 2026-09-25) ──
	_check_overflow(lf, nodes, outs, ins)

	# ── F — real kg along each chain ─────────────────────────────────────────
	# The extruders run their own natraject (operator rulings 2026-09-25 §I4,
	# docs/plant/operator_rulings_2026-09-25.md): the line's start no longer
	# powers laserfilter -> heetafslag -> ... -> weegschaal, so a granulate
	# chain carries kg only once its extruder is started. Every extruder brain
	# is started the way a player does it (hot barrel, the start button) and
	# stepped with LineFlow from here on. Measured 2026-09-25 without this:
	# 0.0 of 31.7 kg reached voorraad_silo on line 1 and on 3B.
	var st : Node = get_node("/root/SimTick")
	var brains : Array = get_tree().get_nodes_in_group("extruder_machine")
	for b in brains:
		var cb := Callable(b, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		var bmod : ExtruderModel = b.get("model")
		bmod.melt_temp = bmod.config.melt_temp_setpoint
		(b.get("_pending") as Dictionary)["start_production"] = true
	var running : int = 0
	var start_ticks : int = 0
	for _k in range(300):
		for b in brains:
			b.call("_on_sim_tick", 0.1)
		lf.call("tick", 0.1)
		start_ticks += 1
		running = 0
		for b in brains:
			if (b.get("model") as ExtruderModel).state == ExtruderModel.State.RUNNING:
				running += 1
		if running == brains.size():
			break
	_check(brains.size() >= 2 and running == brains.size(),
		"F- every extruder brain (%d) is started through its natraject before the kg are fed: %d RUNNING after %.1f s"
		% [brains.size(), running, start_ticks * 0.1])
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
		for b in brains:
			b.call("_on_sim_tick", 0.1)
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
		var thr : int = int(r["through"])
		if thr >= 0:
			# Fed at the feeder, so the machine after it must carry them — and
			# nothing may reach the end without it (the old bypass fed the climb
			# belt straight from the opzetband: shredder 2 moved 0 kg).
			_check(float(moved[thr]) >= REACH_FRAC * fed, "F3a %s: the kg fed at %s pass through %s (%.1f of %.1f kg)"
				% [r["name"], _label(nodes, int(idx[0])), _label(nodes, thr), float(moved[thr]), fed])
			_check(got <= float(moved[thr]) * 1.01 + 0.001, "F3b %s: nothing reaches %s around %s (%.1f kg there, %.1f kg through it)"
				% [r["name"], _label(nodes, last), _label(nodes, thr), got, float(moved[thr])])
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

## True when node `a` carries a BuildMode pin (lf_explicit_outs) naming node `b`.
func _declared(nodes: Array, a: int, b: int) -> bool:
	var na = (nodes[a] as Dictionary).get("node")
	var nb = (nodes[b] as Dictionary).get("node")
	if na == null or nb == null or not is_instance_valid(na) or not is_instance_valid(nb):
		return false
	if not (na as Node).has_meta("lf_explicit_outs"):
		return false
	for o in (na as Node).get_meta("lf_explicit_outs"):
		if o is Dictionary and (o as Dictionary).get("path", NodePath()) == (nb as Node).get_path():
			return true
	return false

## Sum `_moved_kg` of each node in `watch` over `ticks` synchronous ticks,
## feeding `feed_i` for the first `feed_ticks` of them. No frame passes, so the
## Conveyor8 controller's direction_x (moved only in _physics_process) holds.
func _run_ticks(lf: LineFlow, nodes: Array, feed_i: int, feed_ticks: int, ticks: int, watch: Array) -> Dictionary:
	var moved : Dictionary = {}
	for i in watch:
		moved[int(i)] = 0.0
	var fed : float = 0.0
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	for t in ticks:
		if feed_i >= 0 and t < feed_ticks:
			((nodes[feed_i] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(
				feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
				LineFlow.DEFAULT_COMP.duplicate(), "overflow", 0.0, 0.0))
			fed += feed_kg_tick
		lf.call("tick", 0.1)
		for i in watch:
			moved[int(i)] = float(moved[int(i)]) + float((nodes[int(i)] as Dictionary).get("_moved_kg", 0.0))
	moved["fed"] = fed
	return moved

## O — conveyor 8 of the 3A/3B intake. The operator's notes (misc_sources.md
## §1b, confirmed 2026-09-25): C8 normally runs toward C9; when both VSSs are
## FULL it reverses onto the lower C8.5, which feeds the U (stortvak); the U
## feeds nothing. LineFlow's Conveyor8 overlay splits C8's output by its
## direction and reads C8's edge 0 as FORWARD, edge 1 as REVERSE (#138), so the
## edge ORDER is part of the wiring. Before the fix C8's only edge went to
## C8.5 (all kg to the overflow belt whatever the direction), C8.5 fed C9, and
## the U-bay had no inlet.
##
## The kg part HOLDS C8 in reverse (direction_x = -1, no frame passes). It
## proves the wiring and the overlay, not the both-VSS-full trigger: that runs
## into the #139 pack-up cascade, which stops C8.5 3 s and C8 4 s after both
## VSSs report full (found 2026-09-25, not fixed here; see the audit doc).
func _check_overflow(lf: LineFlow, nodes: Array, outs: Dictionary, ins: Dictionary) -> void:
	var lid : String = "line_intake_3a3b"
	var seq : Array = _seq_of(lid)
	print("  -- O: conveyor 8 overflow (%s) --" % lid)
	var c8 : int = _node_at(nodes, lid, _main_index(seq, "transportband_8", 0))
	var c85 : int = _node_at(nodes, lid, _any_index(seq, "transportband_8_5", 0))
	var ub : int = _node_at(nodes, lid, _any_index(seq, "u_bay", 0))
	var c9 : int = _node_at(nodes, lid, _main_index(seq, "transportband_9", 0))
	var ctrl = (nodes[c8] as Dictionary).get("c8_ctrl") if c8 >= 0 else null
	_check(c8 >= 0 and c85 >= 0 and ub >= 0 and c9 >= 0 and ctrl != null,
		"O0 C8 / C8.5 / U-bay / C9 are LineFlow nodes and C8 carries its Conveyor8 controller (%s %s %s %s, ctrl %s)"
		% [_label(nodes, c8), _label(nodes, c85), _label(nodes, ub), _label(nodes, c9), str(ctrl != null)])
	if c8 < 0 or c85 < 0 or ub < 0 or c9 < 0 or ctrl == null:
		return
	_check(outs.get(c8, []) == [c9, c85], "O1 C8 feeds C9 as edge 0 (forward) and C8.5 as edge 1 (reverse) — out %s"
		% _names(nodes, outs.get(c8, [])))
	_check(outs.get(c85, []) == [ub] and ins.get(c85, []) == [c8], "O2 C8.5 is fed ONLY by C8 and feeds ONLY the U-bay — in %s out %s"
		% [_names(nodes, ins.get(c85, [])), _names(nodes, outs.get(c85, []))])
	_check(ins.get(ub, []) == [c85] and (outs.get(ub, []) as Array).is_empty(),
		"O3 the U-bay is fed ONLY by C8.5 and feeds nothing — in %s out %s"
		% [_names(nodes, ins.get(ub, [])), _names(nodes, outs.get(ub, []))])
	_check(ins.get(c9, []) == [c8], "O4 C9 is fed ONLY by C8 — in %s" % _names(nodes, ins.get(c9, [])))
	var undeclared : Array = []
	for pr in [[c8, c9], [c8, c85], [c85, ub]]:
		if not _declared(nodes, int(pr[0]), int(pr[1])):
			undeclared.append("%s -> %s" % [_label(nodes, int(pr[0])), _label(nodes, int(pr[1]))])
	_check(undeclared.is_empty(), "O5 the three overflow edges are declared by the SEQ %s"
		% (str(undeclared) if not undeclared.is_empty() else "(3)"))

	var watch : Array = [c8, c85, ub, c9]
	var t_wall : int = Time.get_ticks_msec()
	# Warm-up: start_line's PLC sequence brings the belts up (no feed).
	_run_ticks(lf, nodes, -1, 0, int(O_WARM_S / 0.1), watch)
	# Forward: C8 as the plant runs it with a VSS free.
	ctrl.set("direction_x", 1.0)
	ctrl.set("direction_target", 1.0)
	var fw : Dictionary = _run_ticks(lf, nodes, c8, int(O_FEED_S / 0.1), int((O_FEED_S + O_DRAIN_S) / 0.1), watch)
	var fed_f : float = float(fw["fed"])
	var u_in_f : float = ((nodes[ub] as Dictionary)["in"] as MaterialBatch).mass_kg
	var u_f : float = float(fw[ub]) + u_in_f
	print("  info  : forward: fed %.1f kg at C8 -> C9 %.1f, C8.5 %.1f, U-bay %.1f kg processed"
		% [fed_f, float(fw[c9]), float(fw[c85]), float(fw[ub])])
	_check(float(fw[c9]) >= REACH_FRAC * fed_f, "O6 C8 forward: the kg fed at C8 reach C9 (%.1f of %.1f kg)" % [float(fw[c9]), fed_f])
	_check(float(fw[c85]) + u_f <= 0.01 * fed_f, "O7 C8 forward: nothing reaches C8.5 or the U-bay (%.2f + %.2f kg of %.1f)"
		% [float(fw[c85]), u_f, fed_f])
	# Reverse: C8 held at full reverse, as after both VSSs report FULL.
	ctrl.set("direction_x", -1.0)
	ctrl.set("direction_target", -1.0)
	var rv : Dictionary = _run_ticks(lf, nodes, c8, int(O_FEED_S / 0.1), int((O_FEED_S + O_DRAIN_S) / 0.1), watch)
	var fed_r : float = float(rv["fed"])
	var dir_after : float = float(ctrl.get("direction_x"))
	# What reached the U-bay in this phase: processed, plus the change in what
	# waits at its inlet.
	var u_r : float = float(rv[ub]) + ((nodes[ub] as Dictionary)["in"] as MaterialBatch).mass_kg - u_in_f
	print("  info  : reverse: fed %.1f kg at C8 -> C9 %.1f, C8.5 %.1f, U-bay %.1f kg processed; C8 direction_x %.2f after; %.1f s wall"
		% [fed_r, float(rv[c9]), float(rv[c85]), float(rv[ub]), dir_after, (Time.get_ticks_msec() - t_wall) / 1000.0])
	_check(is_equal_approx(dir_after, -1.0), "O8 C8 stayed in full reverse through the phase (direction_x %.2f)" % dir_after)
	_check(u_r >= REACH_FRAC * fed_r, "O9 C8 reversed: the kg fed at C8 reach the U-bay through C8.5 (%.1f of %.1f kg)" % [u_r, fed_r])
	_check(float(rv[c9]) <= 0.01 * fed_r, "O10 C8 reversed: nothing reaches C9 (%.2f of %.1f kg)" % [float(rv[c9]), fed_r])
	# Back to forward for the rest of the suite.
	ctrl.set("direction_x", 1.0)
	ctrl.set("direction_target", 1.0)

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] fallback chains %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
