extends Node
## One placeable is ONE `placed_object` and ONE LineFlow node — no machine is
## discovered twice.
##
##   godot --headless --path . res://src/tests/test_flow_node_unique.tscn
##
## WHY THIS FILE EXISTS. Measured 2026-09-25 with dump_line_graph.tscn: every
## intake transportband (1..11, 8_5) and the switch belt on line_intake_3a3b,
## and the switch belt on line_sort, was a LineFlow node TWICE — once as the
## placed body (with its macro_index) and once as a twin with none, at the
## identical win/wout. 30 nodes on the intake line for 17 machines. The twin is
## the body's own `Model` child: PlaceableCatalog.build_node hands `Model` to
## _build_model, and the four builders that called BeltBuilder.build (not
## build_internal) — _m_intake_belt, _m_switch_belt, _m_scraper_conveyor,
## _m_compactor_belt — let it stamp `placeable_id` + group `placed_object` on
## that Model. Every consumer of the group then saw two machines:
##   * LineFlow: the twin had no in-edge, so it was a feed HEAD, and its
##     out-edge double-fed the next belt; it drove the SAME film bed with 0 kg/s
##     every tick, after the body had driven it with the real flow
##   * SwitchBelt / Conveyor8 controllers attached twice to the same deck
##   * BuildMode's snap scan, InspectMode's counts, NpcAutonomyBoard's lookups
## A save never held the twin (_save_layout walks _placed_root's children),
## but build_node re-made it on every load.
##
## The same defect sat in ten more `_m_*` builders that called
## _finalize_placeable(p, …) on their Model: vacuum_unit, vacuum_pump, the six
## hazard placards, overhead_crane, fire_riser, fire_extinguisher,
## drainage_grating, scissor_lift, riveted_steel_column, concrete_v_beam. None
## is on a macro, so the dumps never showed them; placed by hand each was two
## LineFlow nodes too, and on six of them a hatch / valve / pendant collider
## sat under the Model, so K-mode delete aimed at it freed the Model and left
## the body standing. 31 catalog ids in all, measured by A below.
##
## WHAT THIS ASSERTS
##   A  every catalog placeable, built through build_node and left in the tree
##      together (nodes that build themselves in _ready() have done so):
##      A1 its root is `placed_object`
##      A2 no other node of its subtree is
##      A3 every CollisionObject3D in it resolves to the root by BuildMode's
##         K-mode walk (up to the first placed_object)
##      A4 one LineFlow over all of them: no root is more than one node
##      A5 and every root with a flow role is one
##   B  seven macros in one world, 400 m apart, freshly built and after a
##      save/load round trip through BuildMode._save_layout:
##      B1 no LineFlow node is an ancestor of another, or the same Node3D twice
##      B2 no two LineFlow nodes share an id AND win AND wout
##      B3 every LineFlow node is a macro entry (carries macro_id)
##      B4 per line: flow nodes == discoverable placed roots of that macro,
##         one node per (macro_id, macro_index)
##   C  behaviour: one SwitchBelt / Conveyor8 controller per belt; and 950
##      kg/h fed at the intake head for FEED_S — averaged over the last
##      WINDOW_S, every intake belt that carries kg shows a bed on its own film
##      field (the twin drove it with 0 kg/s after the body; all read 0.000)
##
## MUTATIONS (2026-09-25, each red on its own): _m_intake_belt back to
## BeltBuilder.build 10 fail; _m_switch_belt back to build 10; _m_vacuum_pump
## finalizing its Model 3 (A2, A3, A4); LineFlow._discover visiting
## transportband_5 twice 8 (B1, B2, B4, C3c, A4).
##
## Production path: PlaceableCatalog.build_node, BuildMode._build_full_line,
## LineFlow.rebuild / start_line / tick(0.1). The BuildMode writes only its own
## slot file (SLOT), never world_layout.json: load_shared_structure is false,
## so _save_layout never calls WorldLayout.save(). Ghost builds are not
## checked here: ShredderMachine._ready adds even a ghost to placed_object
## (found 2026-09-25, not fixed — see docs/audit/flow_node_twins_2026-09-25.md).

const WATCHDOG_MS : int = 420000
const SLOT : String = "user://__flowunique_factory.json"
const POS_EPS : float = 0.01
const FEED_KG_H : float = 950.0
const FEED_S : float = 90.0
const WINDOW_S : float = 30.0
# A bed is "shown" when the field holds at least this fraction of the kg/m the
# node's own throughput and deck speed give it (thru / speed).
const BED_FRAC : float = 0.5

const LINES : Array = [
	{"line": "line_1",           "origin": Vector3(0.0,    0.0, 0.0)},
	{"line": "line_3a",          "origin": Vector3(400.0,  0.0, 0.0)},
	{"line": "line_3b",          "origin": Vector3(800.0,  0.0, 0.0)},
	{"line": "line_3c",          "origin": Vector3(1200.0, 0.0, 0.0)},
	{"line": "line_intake_3a3b", "origin": Vector3(1600.0, 0.0, 0.0)},
	{"line": "line_sort",        "origin": Vector3(2000.0, 0.0, 0.0)},
	{"line": "line_intake_3c6",  "origin": Vector3(2400.0, 0.0, 0.0)},
]

# The four ids whose builder used to tag its Model — the census must build
# them (anti-vacuity: a census that skipped them would pass on the old code).
const BELT_BUILD_IDS : Array = ["transportband_1", "switch_belt", "scraper_conveyor", "compactor_belt"]

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

## Hang guard: only fires if `_run` aborted on a SCRIPT ERROR after an await.
func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		AtomicFile.delete(SLOT)
		print("Result: FAIL (watchdog — no verdict after %d s)" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

func _placed_in(root: Node) -> Array:
	var out : Array = []
	if root.is_in_group("placed_object"):
		out.append(root)
	for c in root.find_children("*", "", true, false):
		if c.is_in_group("placed_object"):
			out.append(c)
	return out

func _new_bm() -> BuildMode:
	var bm := BuildMode.new()
	bm.layout_path = SLOT
	bm.allow_legacy_fallback = false
	bm.load_shared_structure = false
	return bm

func _label(nodes: Array, i: int) -> String:
	var n3 = (nodes[i] as Dictionary).get("node")
	var mi : int = int(n3.get_meta("macro_index", -1)) if n3 != null and is_instance_valid(n3) else -1
	return "%s#%d[m%d]" % [String((nodes[i] as Dictionary).get("id", "?")), i, mi]

func _run() -> void:
	print("[TEST] flow node uniqueness — one placeable, one placed_object, one LineFlow node")
	AtomicFile.delete(SLOT)
	await _census()

	# ── B — seven macros, freshly built ──────────────────────────────────────
	var bm := _new_bm()
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
	_graph_checks(lf, "built")
	await _behaviour(lf)

	# ── B again, after a save/load round trip ────────────────────────────────
	bm.call("_save_layout")
	lf.queue_free()
	bm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	var bm2 := _new_bm()
	add_child(bm2)                 # _ready → load_layout() from SLOT
	await get_tree().process_frame
	await get_tree().process_frame
	var lf2 := LineFlow.new()
	add_child(lf2)
	await get_tree().process_frame
	lf2.call("rebuild")
	await get_tree().process_frame
	_graph_checks(lf2, "reloaded")
	lf2.queue_free()
	bm2.queue_free()
	await get_tree().process_frame
	AtomicFile.delete(SLOT)
	_check(not AtomicFile.exists_any(SLOT), "Z the slot file %s is gone (and its .bak/.tmp)" % SLOT)
	_finish()

# ── A — the catalog census ──────────────────────────────────────────────────
## Every catalog placeable, built once through build_node and left in the tree
## together (40 m apart, far from the macros), then one LineFlow over them.
func _census() -> void:
	print("  -- A: catalog census --")
	var holder := Node3D.new()
	holder.name = "CensusHolder"
	holder.position = Vector3(0.0, 0.0, -4000.0)
	add_child(holder)
	var built : Array = []
	for it in PlaceableCatalog.items():
		var pid : String = String((it as Dictionary).get("id", ""))
		if pid == "" or PlaceableCatalog.is_retired(pid):
			continue
		var n : Node3D = PlaceableCatalog.build_node(pid, false)
		if n == null:
			continue
		n.position = Vector3(float(built.size() % 20) * 40.0, 0.0, float(built.size() / 20) * 40.0)
		holder.add_child(n)
		built.append(n)
	# Nodes that build themselves in _ready() (ShredderFeedBelt, the opzetband
	# family) have their model after a frame in the tree.
	await get_tree().process_frame
	await get_tree().process_frame
	var ids : Array = []
	var nested : Array = []        # "id: rel/path, …"
	var untagged : Array = []      # root not placed_object
	var misresolved : Array = []   # a collider whose K-mode target is not the root
	var n_colliders : int = 0
	for n in built:
		var pid : String = String((n as Node).get_meta("placeable_id", "?"))
		ids.append(pid)
		if not (n as Node).is_in_group("placed_object"):
			untagged.append(pid)
		var extra : Array = []
		for p in _placed_in(n):
			if p != n:
				extra.append(String((n as Node).get_path_to(p)))
		if not extra.is_empty():
			nested.append("%s: %s" % [pid, ", ".join(extra)])
		# A4 — BuildMode's K-mode delete / select / pole-snap walk up from the
		# hit collider to the FIRST placed_object. Anything under a tagged
		# Model resolved to the Model, and a delete freed the model and left
		# the body standing.
		var cols : Array = (n as Node).find_children("*", "CollisionObject3D", true, false)
		for c in cols:
			n_colliders += 1
			var t : Node = c
			while t != null and not t.is_in_group("placed_object"):
				t = t.get_parent()
			if t != n:
				misresolved.append("%s: %s -> %s" % [pid, String((n as Node).get_path_to(c)),
					String((n as Node).get_path_to(t)) if t != null else "<none>"])
	var missing : Array = []
	for bid in BELT_BUILD_IDS:
		if not ids.has(bid):
			missing.append(bid)
	_check(ids.size() > 100 and missing.is_empty(),
		"A0 the census built %d catalog placeables, including %s (missing %s)" % [ids.size(), str(BELT_BUILD_IDS), str(missing)])
	_check(untagged.is_empty(), "A1 every built placeable's ROOT is placed_object %s"
		% (str(untagged) if not untagged.is_empty() else "(all %d)" % ids.size()))
	_check(nested.is_empty(), "A2 no placeable carries a second placed_object inside it %s"
		% (str(nested) if not nested.is_empty() else "(0 of %d)" % ids.size()))
	_check(n_colliders > 0 and misresolved.is_empty(),
		"A3 every collider inside a placeable resolves to its root the way K-mode walks (%d colliders) %s"
		% [n_colliders, str(misresolved) if not misresolved.is_empty() else ""])

	# A4 — LineFlow over the whole catalog: each placed root is at most ONE
	# flow node, and a root with a flow role is exactly one.
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var per_root : Dictionary = {}     # root instance id -> count
	var outside : int = 0
	for nd in nodes:
		var n3 = (nd as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3):
			continue
		var r : Node = n3
		while r != null and r.get_parent() != holder:
			r = r.get_parent()
		if r == null:
			outside += 1
			continue
		per_root[r.get_instance_id()] = int(per_root.get(r.get_instance_id(), 0)) + 1
	var multi : Array = []
	var absent : Array = []
	var n_flow : int = 0
	for n in built:
		var pid : String = String((n as Node).get_meta("placeable_id", "?"))
		var c : int = int(per_root.get((n as Node).get_instance_id(), 0))
		var flow_role : bool = String(MachineFlow.profile(pid)["role"]) != "none" \
			and not (n as Node).is_in_group("waste_container") and not (n as Node).is_in_group("floor_pile")
		if flow_role:
			n_flow += 1
		if c > 1:
			multi.append("%s x%d" % [pid, c])
		elif flow_role and c == 0:
			absent.append(pid)
	print("  info  : %d LineFlow nodes over %d placeables (%d with a flow role, %d nodes outside the census)"
		% [nodes.size(), ids.size(), n_flow, outside])
	_check(n_flow > 50 and multi.is_empty(), "A4 no catalog placeable is more than one LineFlow node (%d with a flow role) %s"
		% [n_flow, str(multi) if not multi.is_empty() else ""])
	_check(absent.is_empty(), "A5 every placeable with a flow role is a LineFlow node %s"
		% (str(absent) if not absent.is_empty() else "(%d of %d)" % [n_flow, n_flow]))
	lf.queue_free()
	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

# ── B — the flow graph ──────────────────────────────────────────────────────
func _graph_checks(lf: Node, tag: String) -> void:
	print("  -- B (%s): the LineFlow graph --" % tag)
	var nodes : Array = lf.get("_nodes")
	print("  info  : %d LineFlow nodes across %d macros (%s)" % [nodes.size(), LINES.size(), tag])
	# B1 — ancestry. A Node3D reachable from another node's Node3D by walking
	# parents is the same machine seen twice.
	var owner_of : Dictionary = {}        # instance id -> node index
	var nested : Array = []
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 != null and is_instance_valid(n3):
			var iid : int = (n3 as Node).get_instance_id()
			if owner_of.has(iid):
				nested.append("%s is the same Node3D as %s" % [_label(nodes, i), _label(nodes, int(owner_of[iid]))])
			owner_of[iid] = i
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3):
			continue
		var p : Node = (n3 as Node).get_parent()
		while p != null:
			if owner_of.has(p.get_instance_id()):
				nested.append("%s inside %s (%s)" % [_label(nodes, i),
					_label(nodes, int(owner_of[p.get_instance_id()])), String((n3 as Node).get_path())])
				break
			p = p.get_parent()
	_check(nested.is_empty(), "B1 %s: no LineFlow node is an ancestor of another %s"
		% [tag, str(nested) if not nested.is_empty() else "(0 of %d)" % nodes.size()])
	# B2 — same id at the same ports.
	var twins : Array = []
	for i in nodes.size():
		for j in range(i + 1, nodes.size()):
			var a : Dictionary = nodes[i]
			var b : Dictionary = nodes[j]
			if String(a.get("id", "")) != String(b.get("id", "")):
				continue
			if (a["win"] as Vector3).distance_to(b["win"] as Vector3) < POS_EPS \
					and (a["wout"] as Vector3).distance_to(b["wout"] as Vector3) < POS_EPS:
				twins.append("%s = %s" % [_label(nodes, i), _label(nodes, j)])
	_check(twins.is_empty(), "B2 %s: no two LineFlow nodes share an id AND win AND wout %s"
		% [tag, str(twins) if not twins.is_empty() else "(0)"])
	# B3 — every node is a macro entry. In this world nothing but the macros
	# was placed, so a node without macro_id is not a placed machine.
	var stray : Array = []
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3) or not (n3 as Node).has_meta("macro_id"):
			stray.append(_label(nodes, i))
	_check(stray.is_empty(), "B3 %s: every LineFlow node carries a macro_id %s"
		% [tag, str(stray) if not stray.is_empty() else "(all %d)" % nodes.size()])
	# B4 — per line, flow nodes against the placed roots LineFlow should see:
	# macro members that are placed_object, with a flow role, not a sink bin,
	# and not a SEQ entry marked {"flow": false} (BuildMode stamps it
	# lf_placement_only; the sort line's reject belts, 2026-09-25).
	var roots_by_line : Dictionary = {}
	for po in get_tree().get_nodes_in_group("placed_object"):
		if not (po is Node3D) or not po.has_meta("macro_id") or not po.has_meta("placeable_id"):
			continue
		if po.is_in_group("waste_container") or po.is_in_group("floor_pile"):
			continue
		if bool(po.get_meta("lf_placement_only", false)):
			continue
		var pid : String = String(po.get_meta("placeable_id"))
		if String(MachineFlow.profile(pid)["role"]) == "none" or PlaceableCatalog.get_item(pid).is_empty():
			continue
		var lid : String = String(po.get_meta("macro_id"))
		roots_by_line[lid] = int(roots_by_line.get(lid, 0)) + 1
	var nodes_by_line : Dictionary = {}
	var per_slot : Dictionary = {}       # "line:mi" -> count
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3) or not (n3 as Node).has_meta("macro_id"):
			continue
		var lid : String = String((n3 as Node).get_meta("macro_id"))
		nodes_by_line[lid] = int(nodes_by_line.get(lid, 0)) + 1
		var key : String = "%s:%d" % [lid, int((n3 as Node).get_meta("macro_index", -1))]
		per_slot[key] = int(per_slot.get(key, 0)) + 1
	for spec in LINES:
		var lid : String = spec["line"]
		var n_nodes : int = int(nodes_by_line.get(lid, 0))
		var n_roots : int = int(roots_by_line.get(lid, 0))
		var dup : Array = []
		for key in per_slot.keys():
			if String(key).begins_with(lid + ":") and int(per_slot[key]) != 1:
				dup.append("%s x%d" % [key, int(per_slot[key])])
		_check(n_roots > 0 and n_nodes == n_roots and dup.is_empty(),
			"B4 %s %s: %d LineFlow nodes for %d discoverable placed machines, one per macro slot %s"
			% [tag, lid, n_nodes, n_roots, str(dup) if not dup.is_empty() else ""])

# ── C — what the twin did at runtime ────────────────────────────────────────
func _behaviour(lf: Node) -> void:
	print("  -- C: behaviour --")
	var nodes : Array = lf.get("_nodes")
	# C1/C2 — one controller per belt. SwitchBelt / Conveyor8.attach_to names
	# its child; a twin node attached a second one under the Model.
	var n_sw : int = 0
	var n_c8 : int = 0
	for po in get_tree().get_nodes_in_group("placed_object"):
		if not po.has_meta("macro_id"):
			continue
		var pid : String = String(po.get_meta("placeable_id", ""))
		if pid == "switch_belt":
			n_sw += 1
			var c : int = po.find_children("_SwitchBeltCtrl", "", true, false).size()
			_check(c == 1, "C1 %s switch_belt[m%d]: exactly one SwitchBelt controller (%d)"
				% [String(po.get_meta("macro_id")), int(po.get_meta("macro_index", -1)), c])
		elif pid == "transportband_8":
			n_c8 += 1
			var c : int = po.find_children("_Conveyor8Ctrl", "", true, false).size()
			_check(c == 1, "C2 %s transportband_8[m%d]: exactly one Conveyor8 controller (%d)"
				% [String(po.get_meta("macro_id")), int(po.get_meta("macro_index", -1)), c])
	_check(n_sw >= 2 and n_c8 >= 1, "C0 the controllers were looked for (switch belts %d, C8 %d)" % [n_sw, n_c8])

	# C3 — feed the intake line at its head (entry 0: the conveyor into
	# shredder 2 since 2026-09-25, an opzetband before) and read every intake
	# belt's own film bed against its own throughput.
	var head : int = -1
	var belts : Array = []
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 == null or not is_instance_valid(n3) or String((n3 as Node).get_meta("macro_id", "")) != "line_intake_3a3b":
			continue
		var id : String = String((nodes[i] as Dictionary).get("id", ""))
		if int((n3 as Node).get_meta("macro_index", -1)) == 0:
			head = i
		elif id.begins_with("transportband_") and (n3 as Node).has_meta("macro_index"):
			belts.append(i)
	_check(head >= 0 and belts.size() >= 10, "C3a the intake head and its belts are LineFlow nodes (head %d, %d belts)" % [head, belts.size()])
	if head < 0 or belts.is_empty():
		return
	lf.call("start_line")
	var fields : Dictionary = {}          # node index -> its belt-mode field
	for i in belts:
		for v in ((nodes[int(i)] as Dictionary).get("views", []) as Array):
			if v != null and is_instance_valid(v) and bool(v.get("belt_mode")):
				fields[int(i)] = v
				break
	# Averaged over the last WINDOW_S of the feed: a belt's `thru` comes in
	# bursts (C3 and C7 read 1.05 kg/s at an instant on a 0.26 kg/s feed) and
	# the bed slews toward it, so an instant compares a burst with a lag.
	var sums : Dictionary = {}            # i -> [thru, bed, speed, n, max thru]
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var n_ticks : int = int(FEED_S / 0.1)
	var win_from : int = n_ticks - int(WINDOW_S / 0.1)
	for t in n_ticks:
		((nodes[head] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(
			feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
			LineFlow.DEFAULT_COMP.duplicate(), "flow_unique", 0.0, 0.0))
		lf.call("tick", 0.1)
		if t < win_from:
			continue
		for i in fields.keys():
			var f : Node = fields[i]
			var th : float = float((nodes[int(i)] as Dictionary).get("thru", 0.0))
			var s : Array = sums.get(i, [0.0, 0.0, 0.0, 0, 0.0])
			s[0] = float(s[0]) + th
			s[1] = float(s[1]) + float(f.get("_bed_kgpm"))
			s[2] = float(s[2]) + float(f.get("_belt_speed"))
			s[3] = int(s[3]) + 1
			s[4] = maxf(float(s[4]), th)
			sums[i] = s
	var carrying : int = 0
	var bare : Array = []
	for i in belts:
		if not sums.has(int(i)):
			continue
		var s : Array = sums[int(i)]
		var n : float = maxf(float(s[3]), 1.0)
		var thru : float = float(s[0]) / n
		var have : float = float(s[1]) / n
		var speed : float = float(s[2]) / n
		if thru <= 0.01 or speed <= 0.0:
			continue
		carrying += 1
		var want : float = thru / maxf(speed, 0.02)
		print("  info  : %-26s mean thru %.3f kg/s (max %.3f) at %.2f m/s -> mean bed %.3f kg/m (own flow gives %.3f)"
			% [_label(nodes, int(i)), thru, float(s[4]), speed, have, want])
		if have < BED_FRAC * want:
			bare.append("%s %.3f of %.3f kg/m" % [_label(nodes, int(i)), have, want])
	_check(carrying >= 5, "C3b the fed kg reached the intake belts (%d carrying)" % carrying)
	_check(bare.is_empty(), "C3c every intake belt that carries kg shows a bed of at least %.0f %% of its own kg/m %s"
		% [BED_FRAC * 100.0, str(bare) if not bare.is_empty() else "(%d of %d)" % [carrying, carrying]])

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] flow node uniqueness %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
