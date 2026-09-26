extends Node
## The sort line (Sorteerlijn 3A/3B, BuildMode.LINE_SORT_SEQ) is wired the way
## the plant runs it — every edge asserted by name, then by kg.
##
##   godot --headless --path . res://src/tests/test_sort_line_topology.tscn
##
## WHY THIS FILE EXISTS. Measured 2026-09-25 with dump_line_graph.tscn --
## line_sort, after LineFlow's cycle guard was fixed: every side-lane entry of
## the SEQ fell into ONE BuildMode branch_chain, only its last member was wired,
## and the nearest-inlet fallback guessed the rest.
##   opzetband_3a3b[m0]  → bunker[m3]; shredder_1 had NO in-edge (a feed head).
##                         The opzetband's 18 m deck discharges 6 m past the
##                         shredder's throat, so the bunker inlet was nearer.
##   switch_belt[m6]     → Titan incline only; the Tomra incline had no in-edge
##   incline[m9]         → Titan 2, skipping Titan 1 (no in-edge)
##   Titan 2 / Tomra 2   → the FINAL climb belt[m20], skipping the accept
##                         conveyor, the long transfer and shredder 2
##   long transfer[m18]  → Titan 2 (the transfer fed a sorter back)
##   reject belts        → Titan 2 / the accept conveyor, as feed heads
##   shredder_2[m19]     → NO in-edge. Before the guard fix its only in-edge was
##                         its own downstream climb belt (a 2-cycle).
## Fixed in the SEQ with flags only (no index moves — LineFlow._SORT_*_IDX key
## on them): `explicit_from_prev` pins on the whole main chain, streams "titech"
## and "tomra" from the split belt, and {"flow": false} on the reject belts.
##
## THE TOPOLOGY, and what settles each part:
##   0 opzetband → 1 shredder 1 → 2 belt → 3 bunker → 4 belt → 5 belt → 6 split
##       question_answers.json Q16 (operator interview 2026-07-05): "shredder 1
##       -> belt 1012 -> bunker -> belt 1040"; SWI-048 p1 step 1.
##   6 → 9 → 11 → 12 (Titech lane) and 6 → 10 → 13 → 14 (Tomra lane)
##       Two lanes: the SOP sends film to "beide sorteerlijnen" with button
##       2040/2035 (hmi_reference.md §21). The two sorters of a lane run in
##       SERIES — operator ruling 2026-09-25 (AskUserQuestion), matching the two
##       ×0.7 stages of CEDO.xlsx (misc_sources.md §2e).
##   12, 14 → 17 accept conveyor → 18 long transfer → 19 shredder 2 → 20 climb
##       CEDO.xlsx (Titech/Tomra → Shredder 2), the operator's notes
##       (misc_sources.md §1b), the 2026-08-26 bunker/shredder-2 interlock.
##   15, 16 reject belts: NOT flow nodes. A sorter's reject leaves the sim as a
##       counted loss (LineFlow.poly_rejected); on the plant they run to the
##       balenpers (operator 2026-09-25). Magnets 7, 8 are role "none".
##   docs/plant/operator_rulings_2026-09-25.md.
##
## WHAT IS ASSERTED, on one bare BuildMode + LineFlow (no MainWorld, no bales):
##   T  every flow entry is exactly one LineFlow node with the SEQ's id; the
##      magnets and reject belts are placed and are NOT LineFlow nodes
##   E  each node's in- and out-set exact by SEQ index, and every edge out of a
##      SEQ node is explicit (declared, not guessed)
##   C  no cycle of any length on the line, plus an explicit 2-cycle search
##   H  the only feed head is the opzetband, the only dead end the climb belt
##   K  kg fed at the opzetband reach shredder 2 and the climb belt by name,
##      BOTH lanes carry kg, each lane's sorter 1 takes its whole lane and sorter
##      2 takes sorter 1's output, every kg through the split passes both
##      stages (series — parallel wiring puts each stage near half), and no
##      node processes more than was fed (a cycle circulates mass)
##
## KNOWN, OWNED ELSEWHERE — the BeltBuilder twin. build_node's `Model` child of
## a BeltBuilder belt (the switch belt here) is also tagged placed_object, so
## LineFlow discovers it a second time, with no macro_index and no in-edge
## (docs/audit/cycle_guard_swap_2026-09-25.md §6; a separate session is fixing
## it). It cannot carry kg: a head only draws from a bale on its feed point,
## and there are none here. So a twin is named, printed on a NOTE line, and
## excluded from the exact sets, and only while it has NO in-edge — the check
## that makes the exclusion safe. When the fix lands, the NOTE reads 0.
##
## Writes nothing: the BuildMode's layout path is a slot that is never saved
## (only in-game placement calls _save_layout), and shared structure is off.

const LINE_ID     : String = "line_sort"
const FEED_KG_H   : float = 950.0   # under both shredders' ratings (4500 / 2200 kg/h)
const FEED_S      : float = 120.0
const DRAIN_S     : float = 120.0
const REACH_FRAC  : float = 0.5
# No water is added anywhere on this line, so a machine that processes more
# than the kg fed can only be circulating it.
const CIRC_FRAC   : float = 1.05
# Series, by kg: sorter 1 takes (almost) its whole lane, sorter 2 (almost) all
# of sorter 1's output. Parallel wiring would put each near one half.
const SERIES_FRAC : float = 0.8
const LANE_FRAC   : float = 0.2     # the split feeds both lanes, each ≥ 20 % of the feed
const WATCHDOG_MS : int = 300000

# SEQ index → id, for every entry this suite names. A reordered or edited SEQ
# fails T0 loudly instead of silently re-addressing the checks below.
const IDS : Dictionary = {
	0: "opzetband_3a3b", 1: "shredder_1", 2: "transport_belt", 3: "bunker",
	4: "transport_belt", 5: "transport_belt", 6: "switch_belt",
	7: "overband_magnet", 8: "overband_magnet",
	9: "inclined_belt_8m", 10: "inclined_belt_8m",
	11: "titech_sort", 12: "titech_sort", 13: "tomra_sort", 14: "tomra_sort",
	15: "transport_belt", 16: "transport_belt",
	17: "transport_belt", 18: "transport_belt", 19: "shredder_2", 20: "inclined_belt_8m",
}
const NAMES : Dictionary = {
	0: "opzetband", 1: "shredder 1", 2: "belt 1012", 3: "bunker", 4: "belt 1040",
	5: "transfer belt", 6: "split belt", 7: "magnet (Titan)", 8: "magnet (Tomra)",
	9: "incline (Titan)", 10: "incline (Tomra)", 11: "Titan 1", 12: "Titan 2",
	13: "Tomra 1", 14: "Tomra 2", 15: "reject belt (Titan)", 16: "reject belt (Tomra)",
	17: "accept conveyor", 18: "long transfer", 19: "shredder 2", 20: "climb belt",
}
# Placed, not flow nodes.
const NOT_FLOW : Array = [7, 8, 15, 16]
# The operator's topology: SEQ index → the SEQ indices it feeds.
const OUTS : Dictionary = {
	0: [1], 1: [2], 2: [3], 3: [4], 4: [5], 5: [6], 6: [9, 10],
	9: [11], 11: [12], 12: [17],
	10: [13], 13: [14], 14: [17],
	17: [18], 18: [19], 19: [20], 20: [],
}
const LANES : Array = [
	{"name": "Titech lane", "incline": 9, "s1": 11, "s2": 12},
	{"name": "Tomra lane",  "incline": 10, "s1": 13, "s2": 14},
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

func _mi(n3) -> int:
	if n3 == null or not is_instance_valid(n3) or not (n3 as Node3D).has_meta("macro_index"):
		return -1
	if String((n3 as Node3D).get_meta("macro_id", "")) != LINE_ID:
		return -1
	return int((n3 as Node3D).get_meta("macro_index"))

func _label(nodes: Array, i: int) -> String:
	if i < 0:
		return "<none>"
	var nd : Dictionary = nodes[i]
	var mi : int = _mi(nd.get("node"))
	return "%s#%d[m%d%s]" % [String(nd.get("id", "?")), i, mi,
		(" " + String(NAMES[mi])) if NAMES.has(mi) else ""]

func _sorted(a: Array) -> Array:
	var b : Array = a.duplicate()
	b.sort()
	return b

func _run() -> void:
	print("[TEST] sort line topology — by name and by kg")
	var bm := BuildMode.new()
	bm.layout_path = "user://__sorttopology___factory.json"   # never saved (see header)
	bm.allow_legacy_fallback = false
	bm.load_shared_structure = false
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", LINE_ID, Vector3.ZERO, 0.0)
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
	print("  info  : %d LineFlow nodes, %d edges" % [nodes.size(), edges.size()])

	# ── T — the SEQ's machines, and which of them are flow nodes ─────────────
	print("  -- T: SEQ entries and flow nodes --")
	var seq : Array = BuildMode.LINE_SORT_SEQ
	var ids_ok : bool = seq.size() == 21
	for k in IDS.keys():
		if int(k) >= seq.size() or String((seq[int(k)] as Dictionary).get("id", "")) != String(IDS[k]):
			ids_ok = false
	_check(ids_ok, "T0 LINE_SORT_SEQ still has 21 entries with the ids this suite names (%d entries)" % seq.size())
	var node_of : Dictionary = {}      # SEQ index → LineFlow node index
	var dup : Array = []
	for i in nodes.size():
		var mi : int = _mi((nodes[i] as Dictionary).get("node"))
		if mi < 0:
			continue
		if node_of.has(mi):
			dup.append(mi)
		node_of[mi] = i
	for mi in OUTS.keys():
		var i : int = int(node_of.get(mi, -1))
		_check(i >= 0 and String((nodes[i] as Dictionary).get("id", "")) == String(IDS[mi]),
			"T1 %s [m%d] is a LineFlow node with id %s (%s)" % [NAMES[mi], mi, IDS[mi], _label(nodes, i)])
	_check(dup.is_empty(), "T2 no SEQ index is two LineFlow nodes %s" % (str(dup) if not dup.is_empty() else "(0)"))
	var placed : Dictionary = {}       # SEQ index → placed Node3D
	for po in get_tree().get_nodes_in_group("placed_object"):
		var mi : int = _mi(po)
		if mi >= 0:
			placed[mi] = po
	for mi in NOT_FLOW:
		# Anti-vacuity: an entry that was never placed is trivially "not a node".
		_check(placed.has(mi), "T3 %s [m%d] is placed in the world" % [NAMES[mi], mi])
		_check(not node_of.has(mi), "T4 %s [m%d] is NOT a LineFlow node" % [NAMES[mi], mi])
	for mi in [15, 16]:
		var po = placed.get(mi, null)
		_check(po != null and bool((po as Node3D).get_meta(BuildMode.LF_PLACEMENT_ONLY_META, false)),
			"T5 %s [m%d] carries %s (from the SEQ's {\"flow\": false})" % [NAMES[mi], mi, BuildMode.LF_PLACEMENT_ONLY_META])

	# Nodes of this line that are no SEQ entry: only BeltBuilder `Model` twins
	# are tolerated, and only while they cannot carry kg (no in-edge).
	var twins : Array = []
	var strays : Array = []
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3) or _mi(n3) >= 0:
			continue
		var par = (n3 as Node3D).get_parent()
		var pmi : int = _mi(par)
		if pmi >= 0 and String((par as Node3D).get_meta("placeable_id", "")) == String((nodes[i] as Dictionary).get("id", "")):
			twins.append(i)
		else:
			strays.append(_label(nodes, i))
	_check(strays.is_empty(), "T6 every other LineFlow node is a SEQ entry %s" % (str(strays) if not strays.is_empty() else "(0 strays)"))
	var twin_names : Array = []
	var live_twins : Array = []
	for i in twins:
		twin_names.append("%s (Model of [m%d], out %s)" % [_label(nodes, int(i)), _mi((nodes[int(i)] as Dictionary)["node"].get_parent()),
			str((outs.get(int(i), []) as Array).map(func(j): return _label(nodes, int(j))))])
		if not (ins.get(int(i), []) as Array).is_empty():
			live_twins.append(_label(nodes, int(i)))
	print("  NOTE  : %d BeltBuilder Model twin(s) discovered as flow nodes (known defect, fixed separately): %s"
		% [twins.size(), str(twin_names)])
	_check(live_twins.is_empty(), "T7 no twin has an in-edge, so none can carry kg %s" % (str(live_twins) if not live_twins.is_empty() else "(0)"))

	# ── E — exact neighbours, by SEQ index ───────────────────────────────────
	print("  -- E: every edge by name --")
	var want_in : Dictionary = {}
	for a in OUTS.keys():
		for b in OUTS[a]:
			want_in[int(b)] = (want_in.get(int(b), []) as Array) + [int(a)]
	var resolved : bool = true
	for mi in OUTS.keys():
		if not node_of.has(mi):
			resolved = false
	if resolved:
		for mi in _sorted(OUTS.keys()):
			var i : int = int(node_of[mi])
			var got_out : Array = []
			for j in outs.get(i, []):
				got_out.append(_mi((nodes[int(j)] as Dictionary).get("node")))
			var got_in : Array = []
			for j in ins.get(i, []):
				if twins.has(int(j)):
					continue
				got_in.append(_mi((nodes[int(j)] as Dictionary).get("node")))
			var w_out : Array = _sorted(OUTS[mi])
			var w_in : Array = _sorted(want_in.get(mi, []))
			_check(_sorted(got_out) == w_out, "E1 %s [m%d] feeds exactly %s — got %s"
				% [NAMES[mi], mi, str(w_out), str(_sorted(got_out))])
			_check(_sorted(got_in) == w_in, "E2 %s [m%d] is fed by exactly %s — got %s"
				% [NAMES[mi], mi, str(w_in), str(_sorted(got_in))])
			if not w_out.is_empty():
				var n3 : Node3D = (nodes[i] as Dictionary)["node"] as Node3D
				_check(n3.has_meta("lf_explicit_outs") and not (n3.get_meta("lf_explicit_outs") as Array).is_empty(),
					"E3 %s [m%d]'s downstream is declared in the SEQ (explicit), not guessed by geometry" % [NAMES[mi], mi])
	else:
		_check(false, "E0 every SEQ flow entry resolved to a node (see T1)")

	# ── C — cycles ───────────────────────────────────────────────────────────
	print("  -- C: cycles --")
	var cyc : Array = []
	for a in outs.keys():
		for b in outs[a]:
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
				for nx in outs.get(cur, []):
					stack.append(int(nx))
			if hit:
				cyc.append("%s -> %s" % [_label(nodes, int(a)), _label(nodes, int(b))])
	_check(cyc.is_empty(), "C1 no edge on the line sits on a cycle %s" % (str(cyc) if not cyc.is_empty() else "(0)"))
	# The sibling 2-cycle passes every degree check, so it is searched for by name.
	var two : Array = []
	for a in outs.keys():
		for b in outs[a]:
			if (outs.get(int(b), []) as Array).has(int(a)) and int(a) < int(b):
				two.append("%s <-> %s" % [_label(nodes, int(a)), _label(nodes, int(b))])
	_check(two.is_empty(), "C2 no 2-cycle %s" % (str(two) if not two.is_empty() else "(0)"))

	# ── H — feed heads and dead ends ─────────────────────────────────────────
	print("  -- H: heads and dead ends --")
	var heads : Array = []
	var ends : Array = []
	for i in nodes.size():
		if twins.has(i) or String((nodes[i] as Dictionary).get("role", "")) == "sink":
			continue
		if (ins.get(i, []) as Array).is_empty():
			heads.append(_mi((nodes[i] as Dictionary).get("node")))
		if (outs.get(i, []) as Array).is_empty():
			ends.append(_mi((nodes[i] as Dictionary).get("node")))
	_check(_sorted(heads) == [0], "H1 the only feed head is the opzetband [m0] — got %s" % str(_sorted(heads)))
	_check(_sorted(ends) == [20], "H2 the only dead end is the climb belt [m20] (it hands off to transportband 1) — got %s" % str(_sorted(ends)))

	if not resolved:
		_finish()
		return

	# ── K — real kg ──────────────────────────────────────────────────────────
	print("  -- K: kg --")
	var head : Dictionary = nodes[int(node_of[0])]
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var moved : Dictionary = {}
	var first_t : Dictionary = {}
	for mi in OUTS.keys():
		moved[mi] = 0.0
	var fed : float = 0.0
	var rej0 : float = float(lf.get("poly_rejected"))
	var feed_ticks : int = int(FEED_S / 0.1)
	var total_ticks : int = int((FEED_S + DRAIN_S) / 0.1)
	var t_wall : int = Time.get_ticks_msec()
	for t in total_ticks:
		if t < feed_ticks:
			(head["in"] as MaterialBatch).add(MaterialBatch.new(
				feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
				LineFlow.DEFAULT_COMP.duplicate(), "sort_topology", 0.0, 0.0))
			fed += feed_kg_tick
		lf.call("tick", 0.1)
		for mi in moved.keys():
			var m : float = float((nodes[int(node_of[mi])] as Dictionary).get("_moved_kg", 0.0))
			moved[mi] = float(moved[mi]) + m
			if m > 0.0 and not first_t.has(mi):
				first_t[mi] = float(t + 1) * 0.1
	var rejected : float = float(lf.get("poly_rejected")) - rej0
	print("  info  : %d ticks (%.0f s sim) in %.1f s wall; fed %.1f kg at the opzetband; sorters rejected %.1f kg (poly_rejected)"
		% [total_ticks, FEED_S + DRAIN_S, (Time.get_ticks_msec() - t_wall) / 1000.0, fed, rejected])
	for mi in _sorted(OUTS.keys()):
		var bin : MaterialBatch = (nodes[int(node_of[mi])] as Dictionary).get("in", null) as MaterialBatch
		print("  info  : [m%-2d] %-16s processed %7.1f kg, buffered %6.1f kg, first kg at %s"
			% [mi, NAMES[mi], float(moved[mi]), bin.mass_kg if bin != null else 0.0,
			("%.1f s" % float(first_t[mi])) if first_t.has(mi) else "never"])
	_check(fed > 0.0, "K0 kg were fed (%.1f kg)" % fed)
	for mi in [19, 20]:
		var bin : MaterialBatch = (nodes[int(node_of[mi])] as Dictionary).get("in", null) as MaterialBatch
		var got : float = float(moved[mi]) + (bin.mass_kg if bin != null else 0.0)
		_check(got >= REACH_FRAC * fed, "K1 the fed kg reach %s [m%d] by name (%.1f of %.1f kg)" % [NAMES[mi], mi, got, fed])
	for lane in LANES:
		var inc : float = float(moved[int(lane["incline"])])
		var s1 : float = float(moved[int(lane["s1"])])
		var s2 : float = float(moved[int(lane["s2"])])
		_check(inc >= LANE_FRAC * fed, "K2 %s carries kg from the split: its incline processed %.1f kg (≥ %.0f %% of %.1f fed)"
			% [lane["name"], inc, LANE_FRAC * 100.0, fed])
		_check(inc > 0.0 and s1 >= SERIES_FRAC * inc, "K3 %s: %s takes the whole lane — %.1f of the incline's %.1f kg"
			% [lane["name"], NAMES[int(lane["s1"])], s1, inc])
		_check(s1 > 0.0 and s2 >= SERIES_FRAC * s1 and s2 <= s1 * 1.001, "K4 %s: %s takes %s's output (series) — %.1f of %.1f kg"
			% [lane["name"], NAMES[int(lane["s2"])], NAMES[int(lane["s1"])], s2, s1])
	# The ruling itself, by kg: every flake through the split is scanned TWICE.
	# K3/K4 hold per lane even if the split fed the sorter 2s directly (each
	# would still pass "its" kg on), so the sum over both stages is what tells
	# series from parallel: parallel wiring puts each stage near half the split.
	var split_kg : float = float(moved[6])
	var both_s1 : float = float(moved[11]) + float(moved[13])
	var both_s2 : float = float(moved[12]) + float(moved[14])
	_check(split_kg > 0.0 and both_s1 >= SERIES_FRAC * split_kg and both_s2 >= SERIES_FRAC * split_kg,
		"K7 every kg through the split passes a sorter 1 AND a sorter 2 (series): split %.1f kg, stage 1 %.1f, stage 2 %.1f"
		% [split_kg, both_s1, both_s2])
	_check(both_s2 > 0.0 and float(moved[17]) >= SERIES_FRAC * both_s2,
		"K5 both lanes merge on the accept conveyor [m17]: %.1f kg of the two sorter-2s' %.1f" % [float(moved[17]), both_s2])
	var worst : int = -1
	var worst_kg : float = 0.0
	for mi in moved.keys():
		if float(moved[mi]) > worst_kg:
			worst_kg = float(moved[mi])
			worst = int(mi)
	_check(worst_kg <= CIRC_FRAC * fed, "K6 no machine processes more than was fed — nothing circulates (max [m%d] %s %.1f kg, fed %.1f)"
		% [worst, NAMES.get(worst, "?"), worst_kg, fed])
	_finish()

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] sort line topology %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
