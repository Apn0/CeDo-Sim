extends Node
# PROBE (not a suite, not in run.sh): every world suite's fixture line set,
# placed the old way (typed bf through Plant.pc_to_scene, which rotates the
# frame twice) and in the frame the game fits from the shell (building_frame.gd).
# Per line: machines under the shell roof. Per set: machine footprints of
# DIFFERENT lines that overlap in plan. Plus each line's bf footprint alone, and
# the replacement layouts with a count of footprints that cross a shell wall
# (that count includes the halls' pillars and partitions, so it is a hint, not
# a verdict). Measured 2026-09-25 with it: line 3A from bf(4,22) 31/39 under
# the roof the old way, 39/39 fitted; the lump-cart set overlapped in 30 places
# fitted at its old spacing, 0 at bf y 10/31/52 + line 1 at bf(175,92).
#
# Headless, on a COPY of the userdata (it boots MainWorld; world saves are
# redirected, its slot's files restored):
#   APPDATA=<copy> godot --headless --path . res://src/tests/probe_bf_sets.tscn

const BFrame := preload("res://src/tests/building_frame.gd")
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
const SLOT := "__bfsetsprobe__"
const PROTECT : Array[String] = ["user://world_layout.json", "user://__bfsetsprobe___save.json", "user://__bfsetsprobe___factory.json"]

const CANDIDATES := {
	"D2 3c@44+3a@22": [["line_3c", Vector2(4, 44)], ["line_3a", Vector2(4, 22)]],
	"E2 3a@10 3b@31 3c@52 + line_1 at his start": [["line_3a", Vector2(4, 10)], ["line_3b", Vector2(4, 31)], ["line_3c", Vector2(4, 52)], ["line_1", "his"]],
	"E3 3a@10 3b@31 3c@52 + line_1@bf(175,92)": [["line_3a", Vector2(4, 10)], ["line_3b", Vector2(4, 31)], ["line_3c", Vector2(4, 52)], ["line_1", Vector2(175, 92)]],
	"F2 3c@22 (qa_loop)": [["line_3c", Vector2(4, 22)]],
	"G probes 3b@42+sort@22": [["line_3b", Vector2(4, 42)], ["line_sort", Vector2(4, 22)]],
}
const SETS := {
	"A 3a (regression/jam/nav/spawn/id3a)": [["line_3a", Vector2(4, 22)]],
	"B 3b (id3b)": [["line_3b", Vector2(4, 42)]],
	"C 3c (id3c)": [["line_3c", Vector2(4, 22)]],
	"D 3c+3a (tagsnap/l3c/waslijn3c)": [["line_3c", Vector2(4, 62)], ["line_3a", Vector2(4, 22)]],
	"E 1+3a+3b+3c (lump carts)": [["line_1", Vector2(4, 82)], ["line_3a", Vector2(4, 22)], ["line_3b", Vector2(4, 42)], ["line_3c", Vector2(4, 65)]],
	"F 3c@0,0 (qa_loop)": [["line_3c", Vector2(0, 0)]],
}

var _backups := {}
var _world : Node3D = null
var _tris : Dictionary = {}
var _fr : Dictionary = {}
var _fy : float = 0.0

func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU

func _ready() -> void:
	get_tree().create_timer(1500.0).timeout.connect(func(): print("Result: FAIL (watchdog)"); get_tree().quit(2))
	for p in PROTECT:
		_backups[p] = FileAccess.get_file_as_bytes(p) if FileAccess.file_exists(p) else null
	WorldLayout.layout_path_override = "user://__bfsetsprobe___world_layout.json"
	var bus := get_node_or_null("/root/EventBus")
	bus.set_meta("pending_save_name", SLOT)
	bus.set_meta("pending_is_new_save", false)
	_world = (load("res://src/scenes/world/MainWorld.tscn") as PackedScene).instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	var waited := 0
	for _i in range(600):
		await get_tree().process_frame
		waited += 1
		if waited >= 80 and not BFrame.fitted(_world).is_empty():
			break
	_fr = BFrame.fitted(_world)
	print("[S] fitted frame after %d frames: %s" % [waited, str(_fr)])
	_fy = Plant.floor_top_y()
	_tris = BFrame.shell_triangles(_world)
	var bm = _world.get("build_mode")

	# Phase 1: each line alone in the fitted frame at bf(4, 30): its bf footprint.
	for lid in ["line_1", "line_3a", "line_3b", "line_3c"]:
		var nodes : Array = await _build(bm, lid, BFrame.to_scene(_fr, Vector2(4, 30), _fy), BFrame.forward_rot_y(_fr))
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for n in nodes:
			for c in _plan_corners(n):
				var b := BFrame.from_scene(_fr, c)
				lo = Vector2(minf(lo.x, b.x), minf(lo.y, b.y))
				hi = Vector2(maxf(hi.x, b.x), maxf(hi.y, b.y))
		print("[S] %s alone at bf(4,30): %d machines, bf x %.1f..%.1f, y %.1f..%.1f (y from start %+.1f..%+.1f)" % [lid, nodes.size(), lo.x, hi.x, lo.y, hi.y, lo.y - 30.0, hi.y - 30.0])
		_free(nodes)
		await get_tree().process_frame

	# Phase 2: each suite's set, old mapping vs fitted frame.
	for key in SETS.keys():
		for mode in ["OLD", "FIT"]:
			var per_line : Array = []
			var all_nodes : Array = []
			for spec in SETS[key]:
				var lid : String = spec[0]
				var sbf : Vector2 = spec[1]
				var start : Vector3
				var rot : float
				if mode == "OLD":
					start = Plant.pc_to_scene(_bf_to_pc(sbf))
					var fd : Vector3 = (Plant.pc_to_scene(_bf_to_pc(sbf + Vector2(1, 0))) - start).normalized()
					rot = atan2(-fd.x, -fd.z)
				else:
					start = BFrame.to_scene(_fr, sbf, _fy)
					rot = BFrame.forward_rot_y(_fr)
				var nodes : Array = await _build(bm, lid, start, rot)
				var roofed := 0
				for n in nodes:
					if BFrame.under_roof(_tris, Vector3(n.global_position.x, _fy, n.global_position.z)):
						roofed += 1
				per_line.append("%s@%s %d/%d" % [lid, str(sbf), roofed, nodes.size()])
				all_nodes.append([lid, nodes])
			var overlaps := 0
			for i in range(all_nodes.size()):
				for j in range(i + 1, all_nodes.size()):
					for a in all_nodes[i][1]:
						var ra := _plan_rect(a)
						for b in all_nodes[j][1]:
							if ra.intersects(_plan_rect(b)):
								overlaps += 1
			print("[S] %s %s: under roof %s; cross-line footprint overlaps %d" % [key, mode, ", ".join(per_line), overlaps])
			for e in all_nodes:
				_free(e[1])
			await get_tree().process_frame
	# Phase 3: the replacement layouts, fitted frame only, plus wall crossings.
	await _candidates(bm)
	_end()

func _candidates(bm) -> void:
	var walls2 : Array = []
	for t in _tris["walls"]:
		walls2.append(PackedVector2Array([Vector2(t[0].x, t[0].z), Vector2(t[1].x, t[1].z), Vector2(t[2].x, t[2].z)]))
	for key in CANDIDATES.keys():
		var per_line : Array = []
		var all_nodes : Array = []
		for spec in CANDIDATES[key]:
			var lid : String = spec[0]
			var start : Vector3
			if spec[1] is String:
				start = WorldLayout.get_line_start("1", Vector3.ZERO)
				start.y = _fy
			else:
				start = BFrame.to_scene(_fr, spec[1], _fy)
			var nodes : Array = await _build(bm, lid, start, BFrame.forward_rot_y(_fr))
			var roofed := 0
			var crossing := 0
			for n in nodes:
				if BFrame.under_roof(_tris, Vector3(n.global_position.x, _fy, n.global_position.z)):
					roofed += 1
				var r := _plan_rect(n)
				var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
				for w in walls2:
					if not Geometry2D.intersect_polygons(rp, w).is_empty():
						crossing += 1
						break
			per_line.append("%s@%s roof %d/%d, wall-crossing %d" % [lid, str(spec[1]), roofed, nodes.size(), crossing])
			all_nodes.append([lid, nodes])
		var overlaps := 0
		for i in range(all_nodes.size()):
			for j in range(i + 1, all_nodes.size()):
				for a in all_nodes[i][1]:
					var ra := _plan_rect(a)
					for b in all_nodes[j][1]:
						if ra.intersects(_plan_rect(b)):
							overlaps += 1
		print("[C] %s: %s; cross-line overlaps %d" % [key, "; ".join(per_line), overlaps])
		for e in all_nodes:
			_free(e[1])
		await get_tree().process_frame
	# the current layouts, wall-crossings only, for the before column
	for key in SETS.keys():
		var per : Array = []
		for mode in ["OLD", "FIT"]:
			var tot := 0
			var nodes_all : Array = []
			for spec in SETS[key]:
				var lid : String = spec[0]
				var sbf : Vector2 = spec[1]
				var start : Vector3
				var rot : float
				if mode == "OLD":
					start = Plant.pc_to_scene(_bf_to_pc(sbf))
					var fd : Vector3 = (Plant.pc_to_scene(_bf_to_pc(sbf + Vector2(1, 0))) - start).normalized()
					rot = atan2(-fd.x, -fd.z)
				else:
					start = BFrame.to_scene(_fr, sbf, _fy)
					rot = BFrame.forward_rot_y(_fr)
				var nodes : Array = await _build(bm, lid, start, rot)
				for n in nodes:
					var r := _plan_rect(n)
					var rp := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)])
					for w in walls2:
						if not Geometry2D.intersect_polygons(rp, w).is_empty():
							tot += 1
							break
				nodes_all.append(nodes)
			per.append("%s wall-crossing %d" % [mode, tot])
			for ns in nodes_all:
				_free(ns)
			await get_tree().process_frame
		print("[W] %s: %s" % [key, ", ".join(per)])

func _build(bm, lid: String, start: Vector3, rot: float) -> Array:
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[lid] = {}
	bm.call("_build_full_line", lid, start, rot)
	for _i in range(6):
		await get_tree().process_frame
	var out : Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("macro_id") and String(n3.get_meta("macro_id")) == lid and n3.has_meta("placeable_id") and not n3.has_meta("_probe_seen"):
			n3.set_meta("_probe_seen", true)
			out.append(n3)
	return out

func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.get_parent().remove_child(n)
			n.free()

## Plan-view (scene XZ) rect of a machine's visual AABB.
func _plan_rect(n: Node3D) -> Rect2:
	var cs := _plan_corners(n)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for c in cs:
		lo = Vector2(minf(lo.x, c.x), minf(lo.y, c.z))
		hi = Vector2(maxf(hi.x, c.x), maxf(hi.y, c.z))
	# shrink 5 cm so touching neighbours do not count as overlapping
	return Rect2(lo + Vector2(0.05, 0.05), (hi - lo) - Vector2(0.1, 0.1))

func _plan_corners(n: Node3D) -> Array:
	var box := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null or not m.visible:
			continue
		var bb : AABB = m.global_transform * m.get_aabb()
		box = bb if first else box.merge(bb)
		first = false
	if first:
		box = AABB(n.global_position, Vector3.ZERO)
	var out : Array = []
	for i in range(8):
		out.append(box.get_endpoint(i))
	return out

func _end() -> void:
	_world.queue_free()
	await get_tree().process_frame
	for p in PROTECT:
		var d = _backups.get(p, null)
		if d == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		elif FileAccess.get_file_as_bytes(p) != d:
			var f := FileAccess.open(p, FileAccess.WRITE); f.store_buffer(d); f.close()
	print("Result: PROBE done")
	get_tree().quit(0)
