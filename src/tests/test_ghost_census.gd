extends Node
## A placement GHOST is never a placed_object, and never a LineFlow node.
##
##   godot --headless --path . res://src/tests/test_ghost_census.tscn
##
## WHY THIS FILE EXISTS. Measured 2026-09-25 (probe_shredder_ghost_flow):
## `PlaceableCatalog.build_node("shredder_1" / "shredder_2", true)` — the ghost —
## was in group `placed_object` once it had been in the tree for a frame. The
## body of both ids is ShredderMachine.gd even for a ghost, build_node stamps
## `placeable_id` on it before it looks at the flag, and ShredderMachine._ready
## added itself to `placed_object` without knowing it was a ghost. build_node
## itself gates that group on `not ghost`, and every consumer of the group
## trusts it: BuildMode's snap scan says so in a comment ("the ghost … is NOT in
## this group"), and LineFlow._discover, K-mode delete / select / pole snap,
## InspectMode, NpcAutonomyBoard and ContainerGuide iterate it. One LineFlow
## rebuild over a raw shredder ghost made it a flow node with no in-edge, a feed
## HEAD, at the ghost's position.
##
## What it did NOT reach, measured by the same probe: BuildMode's own placement.
## `_spawn_ghost` runs `_make_preview_inert` (2026-09-06) BEFORE add_child, so
## the script is off before `_ready` can run. In continuous placement
## `_place_current` calls `line_flow.rebuild()` with the ghost alive at the
## cursor (4 of 4 placements), and the ghost was never a flow node. So the defect
## lived in the catalog's contract — `ghost = true` → no `placed_object` — and
## anything that builds a ghost without that sanitiser (ContainerGuide does, for
## its container ids) depended on luck. Fixed at the source: ShredderMachine no
## longer adds itself; build_node tags the real body (`placed_object` at its one
## non-ghost site), as it does for every other placeable.
##
## WHAT THIS ASSERTS
##   G  every catalog id, built with ghost = true and left in the tree together
##      for two frames (every root has run _ready):
##      G0 the census is not vacuous: > 100 ghosts, the scripted-body ids among
##         them, all ready
##      G1 no node inside any ghost is `placed_object`
##      G2 one LineFlow rebuilt over all of them has 0 nodes
##   R  the real shredders are unchanged, in the same scene: a real shredder_1
##      and shredder_2 beside the ghosts are `placed_object` and `shredder`, have
##      their rated capacity from `_ready`, and the same LineFlow now has exactly
##      those two nodes (positive control for G2)
##   P  BuildMode's own continuous placement of each shredder: two placements
##      with the ghost alive across each `line_flow.rebuild()`; the rebuild saw
##      each new machine, and no LineFlow node is the ghost or lies under it
## Other behaviour groups a raw ghost joins are printed as `info` and are not
## gated (see docs/audit/shredder_ghost_placed_object_2026-09-25.md §5).
##
## MUTATIONS (2026-09-25): see the audit doc §4.
##
## Writes only its own slot file (SLOT): the BuildMode has
## load_shared_structure = false, so _save_layout never calls
## WorldLayout.save().

const WATCHDOG_MS : int = 240000
const SLOT : String = "user://__ghostcensus_factory.json"

# Placeables whose BODY is a script (PlaceableCatalog.build_node's body switch):
# a script's _ready is where a ghost can register itself. The census must build
# every one of them, or it would pass on the old code.
const SCRIPTED_BODY_IDS : Array = ["shredder_1", "shredder_2", "laser_filter", "kopfilter",
	"lump_cart", "waste_container", "scrap_bin", "wardrobe_locker", "silo_level_sensor"]
# Pure markers a ghost may keep (BuildMode._make_preview_inert keeps them too).
const MARKER_GROUPS : Array = ["machine_leg", "machine_foot", "steam_plume"]

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

func _under(n: Node, root: Node) -> bool:
	var p : Node = n
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false

func _run() -> void:
	print("[TEST] ghost census — a placement ghost is never placed_object or a LineFlow node")
	AtomicFile.delete(SLOT)
	await _census()
	await _placement()
	AtomicFile.delete(SLOT)
	_check(not AtomicFile.exists_any(SLOT), "Z the slot file %s is gone (and its .bak/.tmp)" % SLOT)
	_finish()

# ── G + R — every catalog ghost, then two real shredders beside them ─────────
func _census() -> void:
	print("  -- G: catalog ghost census --")
	var holder := Node3D.new()
	holder.name = "GhostCensus"
	add_child(holder)
	var ghosts : Array = []          # [id, root]
	for it in PlaceableCatalog.items():
		var pid : String = String((it as Dictionary).get("id", ""))
		if pid == "" or PlaceableCatalog.is_retired(pid):
			continue
		var g : Node3D = PlaceableCatalog.build_node(pid, true)
		if g == null:
			continue
		g.position = Vector3(float(ghosts.size() % 20) * 40.0, 0.0, float(ghosts.size() / 20) * 40.0)
		holder.add_child(g)
		ghosts.append([pid, g])
	await get_tree().process_frame
	await get_tree().process_frame

	var ids : Array = []
	var not_ready : Array = []
	var placed : Array = []          # "id: rel/path"
	var groups_by_id : Dictionary = {}   # id -> [group@rel, …] (info)
	for e in ghosts:
		var pid : String = String(e[0])
		var g : Node = e[1]
		ids.append(pid)
		if not g.is_node_ready():
			not_ready.append(pid)
		var all : Array[Node] = g.find_children("*", "", true, false)
		all.append(g)
		for n in all:
			if n.is_in_group("placed_object"):
				placed.append("%s: %s" % [pid, String(g.get_path_to(n))])
			for grp in n.get_groups():
				var gs : String = String(grp)
				if gs.begins_with("_") or MARKER_GROUPS.has(gs) or gs == "placed_object":
					continue
				var tag : String = "%s@%s" % [gs, String(g.get_path_to(n))]
				var lst : Array = groups_by_id.get(pid, [])
				if not lst.has(tag):
					lst.append(tag)
				groups_by_id[pid] = lst
	var missing : Array = []
	for sid in SCRIPTED_BODY_IDS:
		if not ids.has(sid):
			missing.append(sid)
	# HMI panels get an Hmi.gd body (the Control category carries hmi_id).
	var n_hmi : int = 0
	for pid in ids:
		var item : Dictionary = PlaceableCatalog.get_item(String(pid))
		if String(item.get("category", "")) == "Control" and item.has("hmi_id"):
			n_hmi += 1
	_check(ids.size() > 100 and missing.is_empty() and n_hmi > 0 and not_ready.is_empty(),
		"G0 the census built %d ghosts, incl. every scripted body %s and %d HMI panel(s), all ready (missing %s, not ready %s)"
		% [ids.size(), str(SCRIPTED_BODY_IDS), n_hmi, str(missing), str(not_ready)])
	_check(placed.is_empty(), "G1 no node inside a placement ghost is placed_object %s"
		% (str(placed) if not placed.is_empty() else "(0 of %d ghosts)" % ids.size()))
	for pid in groups_by_id.keys():
		print("  info  : ghost %-22s joins %s" % [String(pid), str(groups_by_id[pid])])

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var seen : Array = []
	for nd in nodes:
		seen.append(String((nd as Dictionary).get("id", "?")))
	_check(nodes.is_empty(), "G2 one LineFlow over all %d ghosts has 0 nodes %s"
		% [ids.size(), str(seen) if not seen.is_empty() else ""])

	# ── R — the real shredders, in the same scene, same LineFlow ────────────
	print("  -- R: the real shredders beside the ghosts --")
	var real : Array = []
	for rid in ["shredder_1", "shredder_2"]:
		var r : Node3D = PlaceableCatalog.build_node(rid, false)
		r.position = Vector3(float(real.size()) * 40.0, 0.0, -200.0)
		holder.add_child(r)
		real.append(r)
	await get_tree().process_frame
	await get_tree().process_frame
	var want_rate : Dictionary = {"shredder_1": ShredderMachine.RATED_COARSE, "shredder_2": ShredderMachine.RATED_FINE}
	for r in real:
		var rid : String = String((r as Node).get_meta("placeable_id", "?"))
		var rate : float = float((r as Node).get("rated_kg_h"))
		_check((r as Node).is_in_group("placed_object") and (r as Node).is_in_group("shredder")
				and is_equal_approx(rate, float(want_rate.get(rid, -1.0))),
			"R1 real %s: placed_object %s, shredder %s, rated %.0f kg/h (want %.0f)"
			% [rid, str((r as Node).is_in_group("placed_object")), str((r as Node).is_in_group("shredder")),
				rate, float(want_rate.get(rid, -1.0))])
	lf.call("rebuild")
	nodes = lf.get("_nodes")
	var real_nodes : int = 0
	var ghost_nodes : Array = []
	for nd in nodes:
		var n3 = (nd as Dictionary).get("node")
		if n3 != null and is_instance_valid(n3) and real.has(n3):
			real_nodes += 1
		else:
			ghost_nodes.append(String((nd as Dictionary).get("id", "?")))
	_check(nodes.size() == 2 and real_nodes == 2,
		"R2 the same LineFlow sees exactly the two real shredders (%d nodes, %d real, other %s)"
		% [nodes.size(), real_nodes, str(ghost_nodes)])
	lf.queue_free()
	holder.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

# ── P — BuildMode's continuous placement, ghost alive across the rebuild ─────
func _placement() -> void:
	print("  -- P: BuildMode continuous placement --")
	var bm := BuildMode.new()
	bm.layout_path = SLOT
	bm.allow_legacy_fallback = false
	bm.load_shared_structure = false
	add_child(bm)
	var lf := LineFlow.new()
	add_child(lf)
	bm.line_flow = lf
	await get_tree().process_frame
	var x : float = 0.0
	var placed : int = 0
	for id in ["shredder_1", "shredder_2"]:
		bm.call("_enter_placing", id)
		await get_tree().process_frame
		await get_tree().process_frame
		var g : Node3D = bm.get("_ghost") as Node3D
		if g == null:
			_check(false, "P0 %s: BuildMode spawned a placement ghost" % id)
			continue
		for k in 2:
			g.visible = true
			g.global_position = Vector3(x, 0.0, 0.0)
			x += 12.0
			bm.call("_place_current")             # build, save, line_flow.rebuild()
			placed += 1
			var alive : bool = bm.get("_ghost") == g and is_instance_valid(g) and g.is_inside_tree()
			var nodes : Array = lf.get("_nodes")
			var under : Array = []
			for nd in nodes:
				var n3 = (nd as Dictionary).get("node")
				if n3 != null and is_instance_valid(n3) and _under(n3, g):
					under.append(String((nd as Dictionary).get("id", "?")))
			_check(alive and nodes.size() == placed and under.is_empty(),
				"P1 %s placement %d: ghost alive at the rebuild %s, LineFlow %d nodes for %d placed, %d of them the ghost %s"
				% [id, k + 1, str(alive), nodes.size(), placed, under.size(), str(under) if not under.is_empty() else ""])
			await get_tree().process_frame
		bm.call("_clear_ghost")
		await get_tree().process_frame
	lf.queue_free()
	bm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _finish() -> void:
	_done = true
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] ghost census %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
