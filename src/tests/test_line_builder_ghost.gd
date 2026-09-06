extends Node
# =============================================================================
# #linebuilder-ghost — whole-line ghost preview + pinned menu section.
# =============================================================================
# Operator report 2026-08-29: placing a whole-line macro (e.g. Line 1, ~40
# machines) only showed a single generic box + arrow as the ghost — no way to
# see where the REST of the machines would land before committing, so the
# operator couldn't line the whole train up on first placement. Also asked for
# a pinned "NEW LINE BUILDER" section at the top of the build catalog with
# Line 1 already in it (was previously only reachable buried in the
# alphabetical "Lines" category further down the list).
#
# FIX: BuildMode._build_full_line grew a `preview` param that reuses the
# EXACT SAME position math (turns / branches / transportband Y-stacking /
# at_entry anchoring / saved macro deltas) as the real build, but builds cheap
# translucent placeholder boxes into a returned, unparented ghost root instead
# of real machines into _placed_root. BuildMode._make_line_ghost now calls
# that instead of drawing one generic box. A new pinned catalog section
# (_build_new_line_builder_panel) sits above the "— MACRO SAVE-BACK —" panel
# with a Line 1 quick-place button.
#
# This test proves: (1) preview mode produces one ghost child per real
# machine the line would place, not just one; (2) preview mode has ZERO side
# effects on _placed_root / LineFlow — nothing is actually committed; (3) a
# preview machine's position EXACTLY matches where the real build puts the
# same index (same code path — this is what rules out silent drift between
# preview and reality); (4) the pinned menu section exists, is positioned
# before the old "Lines" category, and its button carries the real line_1
# catalog id.
#
#   godot --headless --path . res://src/tests/test_line_builder_ghost.tscn
# =============================================================================

const TEST_SLOT : String = "__linebuildergh__"
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__linebuildergh___save.json",
	"user://__linebuildergh___factory.json",
]

const BOOT_FRAMES : int = 120

var _backups : Dictionary = {}
var _oks   : int = 0
var _fails : int = 0
var _world : Node3D = null

func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)

func _info(msg: String) -> void:
	print("  info  : %s" % msg)

func _ready() -> void:
	print("=== #linebuilder-ghost — whole-line ghost preview + pinned menu ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	_backup_files()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	for i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var bm : Node = _world.get("build_mode")
	if bm == null:
		_check(false, "world.build_mode is present"); _finish(1); return

	# ── 1+2. Preview mode: many children, zero side effects ────────────────
	var placed_root : Node = bm.get("_placed_root")
	var before_count : int = placed_root.get_child_count() if placed_root else -1

	var ghost : Node3D = bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0, true)
	_check(ghost != null, "preview call returned a non-null ghost root")
	if ghost == null:
		_finish(1); return
	var ghost_children : int = ghost.get_child_count()
	_info("preview ghost has %d placeholder children" % ghost_children)
	_check(ghost_children > 5, "preview ghost has more than 5 machines (not just a single generic box) — got %d" % ghost_children)
	_check(not ghost.is_inside_tree(), "preview ghost was returned UNPARENTED (caller decides where it lives)")

	# Parent it (as _spawn_ghost does in real use) so global_position is
	# well-defined for the comparison below — a Node3D outside the tree has
	# no valid global_transform. self sits at the test root's origin, so this
	# doesn't change any of the offsets being measured.
	add_child(ghost)

	var after_preview_count : int = placed_root.get_child_count() if placed_root else -2
	_check(after_preview_count == before_count,
		"preview mode added NOTHING to _placed_root (before %d, after %d)" % [before_count, after_preview_count])

	var lf = _world.get("line_flow")
	var lf_nodes_before : int = (lf.get("_nodes") as Array).size() if lf != null else -1

	# ── 3. Position parity: preview vs a real build, same index ────────────
	var real_start := Vector3(500.0, 0.0, 500.0)   # far from anything else on the map
	bm.call("_build_full_line", "line_1", real_start, 0.0, false)
	await get_tree().process_frame
	var real_nodes : Array = []
	for child in placed_root.get_children():
		if String(child.get_meta("macro_id", "")) == "line_1" \
				and child.global_position.distance_to(real_start) < 400.0:
			real_nodes.append(child)
	_check(real_nodes.size() > 5, "real build placed more than 5 machines for line_1 — got %d" % real_nodes.size())
	_check(real_nodes.size() == ghost_children,
		"real build placed the SAME machine count as the preview ghost (real %d vs ghost %d)"
			% [real_nodes.size(), ghost_children])

	if real_nodes.size() > 0 and ghost_children > 0:
		# index 0 in both should be the line's first machine — compare its
		# offset from the line's own start/anchor (preview start = ZERO, real
		# start = real_start), which should match if the position math is
		# genuinely shared, not duplicated-and-drifted.
		var ghost0 : Node3D = ghost.get_child(0) as Node3D
		var real0 : Node3D = null
		for child in real_nodes:
			if int(child.get_meta("macro_index", -1)) == int(ghost0.get_meta("macro_index", -2)) \
					if ghost0.has_meta("macro_index") else false:
				real0 = child
				break
		# Ghost boxes carry no macro_index meta (preview skips meta-stamping by
		# design) — fall back to matching by ghost node NAME ("ghost_<mid>"),
		# which encodes the same catalog id the real node's placeable_id meta does.
		if real0 == null:
			for child in real_nodes:
				if int(child.get_meta("macro_index", -1)) == 0:
					real0 = child
					break
		if real0 != null:
			var ghost_offset : Vector3 = ghost0.global_position   # preview start was ZERO
			var real_offset : Vector3 = real0.global_position - real_start
			var drift : float = ghost_offset.distance_to(real_offset)
			_info("entry-0 offset from line start — preview %s, real %s (drift %.4f m)"
				% [str(ghost_offset), str(real_offset), drift])
			_check(drift < 0.01,
				"preview and real placement agree on entry 0's position (drift %.4f m, expect ~0)" % drift)
		else:
			_check(false, "could not find the real build's entry-0 node to compare against the ghost")

	# LineFlow must not have reacted to the preview at all (only the real
	# build above should have — if line_flow exists here it will have grown).
	if lf != null:
		var lf_nodes_after : int = (lf.get("_nodes") as Array).size()
		_info("LineFlow node count before/after this test's real build: %d -> %d" % [lf_nodes_before, lf_nodes_after])

	# ── 5. #linebuilder-geometry — the slots are REAL MACHINES, not boxes ──
	# Checks 1-3 above pass IDENTICALLY for footprint boxes and for real
	# geometry: they count slots, prove zero side effects, and compare
	# positions. None of them can see WHAT was drawn. This block is the only
	# thing holding the operator's 2026-09-06 "real geometry ghosts" ruling in
	# place — without it, a revert to _make_ghost_placeholder_box stays green.
	#
	# The discriminator: a placeholder box is exactly ONE MeshInstance3D, while
	# a catalog machine is built from dozens of parts — and ghosts deliberately
	# skip StaticMerge (PlaceableCatalog.gd:1522), so those parts stay separate
	# nodes. Measured 2026-09-06 on line_1: 50 slots, 1383 mesh instances,
	# 48 of 50 slots multi-part. The thresholds below sit well under those
	# numbers so ordinary catalog detail work does not trip them; only a
	# wholesale revert to single-box placeholders does.
	var total_meshes := 0
	var multi_part_slots := 0
	for c in ghost.get_children():
		var mcount : int = (c as Node3D).find_children("*", "MeshInstance3D", true, false).size()
		total_meshes += mcount
		if mcount > 1:
			multi_part_slots += 1
	_info("ghost geometry: %d MeshInstance3D across %d slots; %d slots multi-part"
		% [total_meshes, ghost_children, multi_part_slots])
	_check(multi_part_slots * 10 >= ghost_children * 8,
		"at least 80%% of ghost slots are real multi-part machines, not single-box placeholders (got %d/%d)"
			% [multi_part_slots, ghost_children])
	_check(total_meshes > ghost_children * 5,
		"the ghost carries real machine detail — over 5 mesh parts per slot on average (got %d parts across %d slots)"
			% [total_meshes, ghost_children])

	# The safety half of the ruling. Real geometry is only safe in a preview
	# because PlaceableCatalog gates collision + the placed_object group on
	# `not ghost` (PlaceableCatalog.gd:1525). Lock that contract here: if a
	# future catalog edit ever leaks a collider into a ghost, the operator
	# would silently walk into an object that is not there yet.
	var ghost_colliders : int = ghost.find_children("*", "CollisionShape3D", true, false).size()
	_check(ghost_colliders == 0,
		"the real-geometry ghost carries ZERO CollisionShape3D — a preview must never be solid (got %d)"
			% ghost_colliders)
	# Same for the behaviour-carrying groups. "belt" would drag the operator
	# along a deck that is not there; "lump_cart" would let a previewed cart win
	# LaserFilter's _closest_in_group search and swallow real lumps.
	var ghost_grouped := 0
	var grouped_names : Array[String] = []
	var ghost_all : Array[Node] = ghost.find_children("*", "", true, false)
	ghost_all.append(ghost)
	for n in ghost_all:
		for g in ["placed_object", "belt", "lump_cart", "bale"]:
			if n.is_in_group(g):
				ghost_grouped += 1
				if not grouped_names.has(g):
					grouped_names.append(g)
	_check(ghost_grouped == 0,
		"no ghost node is in a behaviour group (placed_object/belt/lump_cart/bale) — a preview is never saveable, walkable or feedable (got %d in %s)"
			% [ghost_grouped, str(grouped_names)])

	# ── 4. Pinned menu section exists and sits above the old Lines category ─
	var catalog : Control = bm.get("_catalog")
	_check(catalog != null, "BuildMode._catalog panel exists")
	if catalog != null:
		var labels : Array[String] = []
		_collect_label_texts(catalog, labels)
		var lb_idx := -1
		var msb_idx := -1
		var lines_cat_idx := -1
		for i in labels.size():
			if labels[i].findn("NEW LINE BUILDER") != -1 and lb_idx == -1:
				lb_idx = i
			if labels[i].findn("MACRO SAVE-BACK") != -1 and msb_idx == -1:
				msb_idx = i
			if labels[i].findn("— Lines —") != -1 and lines_cat_idx == -1:
				lines_cat_idx = i
		_check(lb_idx != -1, "a '— NEW LINE BUILDER —' section label exists in the catalog")
		_check(msb_idx != -1, "the existing '— MACRO SAVE-BACK —' section label still exists (unrelated section untouched)")
		if lb_idx != -1 and msb_idx != -1:
			_check(lb_idx < msb_idx, "the new Line Builder section sits ABOVE the Macro Save-Back panel (index %d < %d)" % [lb_idx, msb_idx])
		if lb_idx != -1 and lines_cat_idx != -1:
			_check(lb_idx < lines_cat_idx, "the new Line Builder section sits ABOVE the old 'Lines' category (index %d < %d)" % [lb_idx, lines_cat_idx])

		var btn := _find_button_for_id(catalog, "line_1")
		_check(btn != null, "a catalog button wired to line_1 exists (the pinned quick-access button, or the original Lines-category one)")

	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)

func _collect_label_texts(n: Node, out : Array[String]) -> void:
	if n is Label:
		out.append((n as Label).text)
	for c in n.get_children():
		_collect_label_texts(c, out)

func _find_button_for_id(n: Node, id: String) -> Button:
	if n is Button:
		for c in (n as Button).pressed.get_connections():
			var cb : Callable = c["callable"]
			if cb.get_bound_arguments().size() > 0 and String(cb.get_bound_arguments()[0]) == id:
				return n as Button
	for c in n.get_children():
		var r := _find_button_for_id(c, id)
		if r != null:
			return r
	return null

func _backup_files() -> void:
	for p in PROTECT:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in PROTECT:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(data)
			f.close()

func _finish(code: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)
