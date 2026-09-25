extends Node
## PROBE (not a suite): does a shredder placement ghost become a LineFlow node?
##
##   godot --headless --path . res://src/tests/probe_shredder_ghost_flow.tscn
##
## Two paths, measured separately (docs/audit/shredder_ghost_placed_object_2026-09-25.md):
##   P1  BuildMode's own continuous placement: _enter_placing(id) spawns the
##       ghost, _place_current() builds the real machine, saves, and calls
##       line_flow.rebuild() while the ghost stays at the cursor. Twice per id.
##       After each rebuild every LineFlow node is listed with its path, and any
##       node that is the ghost or lies under it is flagged GHOST.
##   P2  The raw catalog ghost: PlaceableCatalog.build_node(id, true), parented,
##       two frames, then one LineFlow rebuild. What groups it joined and what
##       LineFlow node (in / out edges) it became.
## Writes only its own slot file (SLOT); load_shared_structure is false.

const SLOT : String = "user://__shghostprobe_factory.json"
const IDS : Array = ["shredder_1", "shredder_2"]
const WATCHDOG_MS : int = 120000

var _t0 : int = 0
var _done : bool = false

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		AtomicFile.delete(SLOT)
		print("PROBE: watchdog — no end after %d s" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

func _groups_of(root: Node) -> Array:
	var out : Array = []
	var all : Array[Node] = root.find_children("*", "", true, false)
	all.append(root)
	for n in all:
		for g in n.get_groups():
			var gs : String = String(g)
			if gs.begins_with("_"):
				continue   # engine-internal groups (_vp_*, …)
			var tag : String = "%s@%s" % [gs, String(root.get_path_to(n))]
			if not out.has(tag):
				out.append(tag)
	return out

func _under(n: Node, root: Node) -> bool:
	var p : Node = n
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false

func _dump(lf: LineFlow, ghost: Node, tag: String) -> int:
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var n_ghost : int = 0
	print("  [%s] %d LineFlow nodes, %d edges" % [tag, nodes.size(), edges.size()])
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var n3 = nd.get("node")
		var is_g : bool = ghost != null and is_instance_valid(ghost) and n3 != null and is_instance_valid(n3) and _under(n3, ghost)
		if is_g:
			n_ghost += 1
		var ins : Array = []
		var outs : Array = []
		for e in edges:
			if int(e["b"]) == i:
				ins.append(String((nodes[int(e["a"])] as Dictionary).get("id", "?")) + "#" + str(e["a"]))
			if int(e["a"]) == i:
				outs.append(String((nodes[int(e["b"])] as Dictionary).get("id", "?")) + "#" + str(e["b"]))
		print("    #%d %-14s %s  path=%s  in=%s out=%s%s" % [i, String(nd.get("id", "?")),
			str((n3 as Node3D).global_position) if n3 != null and is_instance_valid(n3) else "?",
			String((n3 as Node).get_path()) if n3 != null and is_instance_valid(n3) else "?",
			str(ins), str(outs), "   <== GHOST" if is_g else ""])
	return n_ghost

func _run() -> void:
	print("PROBE: shredder ghost vs LineFlow")
	AtomicFile.delete(SLOT)

	# ── P1 — BuildMode's continuous placement ─────────────────────────────────
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
	for id in IDS:
		print("-- P1 %s: BuildMode._enter_placing -> _place_current x2 --" % id)
		bm.call("_enter_placing", id)
		await get_tree().process_frame
		await get_tree().process_frame
		var g : Node3D = bm.get("_ghost") as Node3D
		print("  ghost %s  script=%s  placed_object=%s  groups=%s" % [
			String(g.name) if g != null else "<null>",
			str(g.get_script()) if g != null else "-",
			str(g.is_in_group("placed_object")) if g != null else "-",
			str(_groups_of(g)) if g != null else "[]"])
		for k in 2:
			g.visible = true
			g.global_position = Vector3(x, 0.0, 0.0)
			x += 12.0
			var before : int = (lf.get("_nodes") as Array).size()
			bm.call("_place_current")            # builds, saves, line_flow.rebuild()
			var after : int = (lf.get("_nodes") as Array).size()
			var still : bool = bm.get("_ghost") == g and is_instance_valid(g)
			print("  place %d: state=%d ghost alive at rebuild=%s  LineFlow nodes %d -> %d"
				% [k + 1, int(bm.get("_state")), str(still), before, after])
			var ng : int = _dump(lf, g, "P1 %s place %d" % [id, k + 1])
			print("  P1 %s place %d: %d LineFlow node(s) are the ghost or under it" % [id, k + 1, ng])
			await get_tree().process_frame
		bm.call("_clear_ghost")
		await get_tree().process_frame
	lf.queue_free()
	bm.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	# ── P2 — the raw catalog ghost ────────────────────────────────────────────
	for id in IDS:
		print("-- P2 %s: PlaceableCatalog.build_node(id, true) in the tree --" % id)
		var holder := Node3D.new()
		add_child(holder)
		var g : Node3D = PlaceableCatalog.build_node(id, true)
		print("  before add_child: script=%s placed_object=%s placeable_id=%s"
			% [str(g.get_script()), str(g.is_in_group("placed_object")), str(g.get_meta("placeable_id", "<none>"))])
		holder.add_child(g)
		g.global_position = Vector3(500.0, 0.0, 0.0)
		await get_tree().process_frame
		await get_tree().process_frame
		print("  after 2 frames: placed_object=%s  groups=%s" % [str(g.is_in_group("placed_object")), str(_groups_of(g))])
		var lf2 := LineFlow.new()
		add_child(lf2)
		await get_tree().process_frame
		lf2.call("rebuild")
		var ng : int = _dump(lf2, g, "P2 %s" % id)
		print("  P2 %s: %d LineFlow node(s) are the ghost or under it" % [id, ng])
		lf2.queue_free()
		holder.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame

	AtomicFile.delete(SLOT)
	_done = true
	print("PROBE: end")
	get_tree().quit(0)
