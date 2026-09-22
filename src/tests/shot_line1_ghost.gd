extends Node
# =============================================================================
# shot_line1_ghost — LOOK at the line-1 whole-line placement ghost.
# =============================================================================
# #linebuilder-geometry (2026-09-06) made every preview slot a real machine
# instead of a footprint box, and test_line_builder_ghost proves that
# GEOMETRICALLY — part counts, collider counts, positions. Nothing proves how it
# READS on screen. This tool produces the picture, so "the fold renders
# correctly" stops being an inference.
#
# Run WINDOWED. --headless has no rendering device, so get_texture() there
# returns nothing and the shot would be blank:
#   Godot --path . res://src/tests/shot_line1_ghost.tscn
#
# Writes into docs/plant/renders/ (operator rule 2026-07-20: renders land in the
# project, never only in user:// — a render nobody can find gets re-made from
# scratch next session), with unique line-coded names (rule 2026-07-15, never a
# shared name that overwrites the previous line's shot):
#   shot_line1_ghost_overview_2026_09_06.png — the whole fold, legs A-F
#   shot_line1_ghost_drumhead_2026_09_06.png — close on the leg-C->D corner
#
# Both frames go through ShotCommon.check_image_content, so a black or flat
# frame FAILS loudly instead of silently "saving" (audit finding C10).
#
# PROTECT/restore is copied from test_line_builder_ghost deliberately: booting
# MainWorld against a test slot writes user:// files, and on 2026-09-06 a
# damaged world_layout.json cost a full harness run of misleading reds.
# =============================================================================

const TEST_SLOT : String = "__line1ghostshot__"
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__line1ghostshot___save.json",
	"user://__line1ghostshot___factory.json",
]
const BOOT_FRAMES : int = 120
const OUT_DIR : String = "res://docs/plant/renders/"
const STAMP : String = "2026_09_16"

var _backups : Dictionary = {}
var _world : Node3D = null
var _fails : int = 0

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

## World-space AABB over every visual part of `root`, in GLOBAL coordinates.
## Node positions alone are not enough — a 9 m flotation tank contributes far
## more than its origin — so this unions each MeshInstance3D's own AABB after
## pushing it through that mesh's global transform.
func _visual_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var seeded := false
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var local : AABB = mi.get_aabb()
		var xf : Transform3D = mi.global_transform
		var world : AABB = xf * local
		if not seeded:
			out = world
			seeded = true
		else:
			out = out.merge(world)
	return out

## Frame `target` from a 3/4 aerial and save. Returns true if the PNG has content.
func _shoot(cam: Camera3D, eye: Vector3, look: Vector3, name_: String) -> bool:
	cam.global_position = eye
	cam.look_at(look, Vector3.UP)
	cam.make_current()
	return await _shoot_current(cam, name_)

## Capture whatever the current camera already frames. Split out of _shoot because
## the plan view sets its basis directly (look_at is degenerate straight down).
func _shoot_current(_cam: Camera3D, name_: String) -> bool:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var outp : String = OUT_DIR + name_
	img.save_png(outp)
	var ok : bool = preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved %s  eye=%s" % [ProjectSettings.globalize_path(outp), str(_cam.global_position)])
	if not ok:
		_fails += 1
	return ok

## Print the ghost's plan-view legs, measured, so the render can be checked
## against LINE_1_SEQ's leg map ("#fold 2026-08-28") instead of eyeballed.
##
## The step from one slot to the next is NOT the leg direction: line 1 lays 7
## stations as side-by-side PAIRS, so the walk zigzags +-135 degrees between a
## machine and its twin. Differencing over a TWO-slot window cancels that jog
## and leaves the leg's own heading, which is then quantised to the nearest
## axis. Sequence order is build order, so the last child (the march arrow that
## _make_line_ghost adds back at the origin) is dropped rather than reported as
## a 109 m leg.
func _dump_legs(ghost: Node3D) -> void:
	var pts : Array = []
	for c in ghost.get_children():
		var n := c as Node3D
		if n != null and String(n.name).begins_with("ghost_"):
			pts.append({"name": String(n.name), "p": n.position})
	if pts.size() < 3:
		print("[LEG] too few named slots to walk (%d)" % pts.size())
		return
	# Quantised heading of the 2-slot window ending at i, as an axis label.
	var axis := func(i: int) -> String:
		var a : Vector3 = pts[maxi(i - 2, 0)]["p"]
		var b : Vector3 = pts[i]["p"]
		var d := Vector2(b.x - a.x, b.z - a.z)
		if d.length() < 0.05:
			return ""
		return ("+X" if d.x > 0.0 else "-X") if absf(d.x) >= absf(d.y) else ("+Z" if d.y > 0.0 else "-Z")
	var leg := 0
	var cur := ""
	var from_i := 0
	for i in range(2, pts.size()):
		var ax : String = axis.call(i)
		if ax == "" or ax == cur:
			continue
		if cur != "":
			_print_leg(leg, cur, pts, from_i, i - 1)
			from_i = i - 1
		cur = ax
		leg += 1
	if cur != "":
		_print_leg(leg, cur, pts, from_i, pts.size() - 1)

func _print_leg(leg: int, ax: String, pts: Array, i0: int, i1: int) -> void:
	var a : Vector3 = pts[i0]["p"]
	var b : Vector3 = pts[i1]["p"]
	var run : float = Vector2(b.x - a.x, b.z - a.z).length()
	print("[LEG %s] %-3s %5.1f m  %-22s -> %-22s  (%d slots)" % [
		char(64 + leg), ax, run, String(pts[i0]["name"]), String(pts[i1]["name"]), i1 - i0 + 1])

func _ready() -> void:
	print("=== shot_line1_ghost — rendering the whole-line placement ghost ===")
	if DisplayServer.get_name() == "headless":
		print("FATAL: run WINDOWED — headless has no rendering device, every frame would be blank.")
		get_tree().quit(2); return
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
		print("FATAL: world.build_mode is null"); _finish(1); return

	# The real path, not a hand-rolled preview: _spawn_ghost is what the operator
	# triggers by picking Lijn 1 in the build catalog, and it is what applies
	# _make_preview_inert. Anything else would be a picture of a different object.
	bm.call("_spawn_ghost", "line_1")
	await get_tree().process_frame
	var ghost : Node3D = bm.get("_ghost") as Node3D
	if ghost == null:
		print("FATAL: _spawn_ghost produced no ghost"); _finish(1); return

	var slots : int = ghost.get_child_count()
	var meshes : int = ghost.find_children("*", "MeshInstance3D", true, false).size()
	var shapes : int = ghost.find_children("*", "CollisionShape3D", true, false).size()
	print("[SHOT] ghost: %d slots, %d MeshInstance3D, %d CollisionShape3D" % [slots, meshes, shapes])

	# Drop it where line 1 actually lives, so the shot shows the train against the
	# real hall rather than floating at the world origin.
	var wl := get_node_or_null("/root/WorldLayout")
	var start := Vector3(-142.696868896484, 0.0, 42.9187507629395)   # world_layout line_starts["1"]
	# get_line_start(id, fallback) takes TWO args (WorldLayout.gd:107) — calling it
	# with one throws and aborts the whole render.
	if wl != null and wl.has_method("get_line_start"):
		var got = wl.call("get_line_start", "1", start)
		if got is Vector3:
			start = got
	ghost.global_position = start
	await get_tree().process_frame

	var box : AABB = _visual_aabb(ghost)
	print("[SHOT] ghost visual AABB pos=%s size=%s" % [str(box.position), str(box.size)])

	# The picture shows a fold; only numbers say WHICH fold. Walk the slots in
	# build order and print a leg break wherever the step direction turns more
	# than 45 degrees, so the render can be read against LINE_1_SEQ's leg map
	# (BuildMode.gd, "#fold 2026-08-28") instead of eyeballed off pixels.
	var _ci := 0
	for c in ghost.get_children():
		var n3 := c as Node3D
		print("[CHILD %2d] %-24s %-18s pos=%s" % [_ci, String(c.name), c.get_class(),
			str(n3.position) if n3 != null else "-"])
		_ci += 1
	_dump_legs(ghost)

	# The first attempt shot the HALL ROOF from outside and the ghost was a speck.
	# Line 1 lives indoors, so the shell has to come off, and the HUD covers a
	# third of the frame. Both are hidden for the capture only — this scene is
	# torn down in _finish, nothing is saved.
	var shell : Node3D = _world.get_node_or_null("BuildingShell") as Node3D
	if shell != null:
		shell.visible = false
		print("[SHOT] BuildingShell hidden for the capture")
	var hud_hidden := 0
	for cl in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var layer := cl as CanvasLayer
		if layer != null and layer.visible:
			layer.visible = false
			hud_hidden += 1
	print("[SHOT] %d CanvasLayer(s) hidden" % hud_hidden)
	await get_tree().process_frame

	# In-game clock is 07:00 (Vroege dienst), so the world sun is barely up and the
	# first captures came out too murky to judge a translucent ghost against a
	# brown floor. Add a capture light rather than fight the day/night cycle.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.05
	key.shadow_enabled = false
	add_child(key)
	key.global_position = box.position + box.size * 0.5 + Vector3(0.0, 80.0, 0.0)
	key.rotation_degrees = Vector3(-62.0, -38.0, 0.0)

	var cam := Camera3D.new()
	cam.far = 4000.0
	cam.keep_aspect = Camera3D.KEEP_WIDTH   # the line's 114 m span is HORIZONTAL
	add_child(cam)

	# ── overview: the whole fold ────────────────────────────────────────────
	# Pull back on the longer horizontal axis so every leg fits, and come in from
	# +X/+Z at roughly 40 degrees — a plan-ish 3/4 that keeps the turns readable
	# (a pure top-down flattens the height differences the fold is full of).
	# Distance derived from the camera's own FOV and the measured span, not guessed:
	# half the span must subtend half the vertical FOV, plus 35 % margin.
	var centre : Vector3 = box.position + box.size * 0.5
	var span : float = maxf(box.size.x, box.size.z)
	var dist : float = (span * 0.5) / tan(deg_to_rad(cam.fov) * 0.5) * 1.12
	var dir : Vector3 = Vector3(0.60, 0.62, 0.50).normalized()
	await _shoot(cam, centre + dir * dist, centre,
		"shot_line1_ghost_overview_%s.png" % STAMP)

	# Straight down: the fold is a PLAN-view claim (legs A-F, turns L,L,R,R,L), and
	# a plan view is the one angle where a wrong turn is unmissable.
	#
	# NOT via look_at: a straight-down direction is PARALLEL to the up vector it
	# takes, which is degenerate — the first attempt came out rolled at an
	# arbitrary angle and the line read as a diagonal. Set the basis directly so
	# world +X is screen-right and world +Z is screen-down, every time.
	cam.global_position = centre + Vector3(0.0, dist * 1.30, 0.0)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.make_current()
	await _shoot_current(cam, "shot_line1_ghost_plan_%s.png" % STAMP)

	# ── drum head: the leg-C -> leg-D corner ────────────────────────────────
	# This is the fold's sharpest claim — the hoekgoot hands material through a
	# 90 degree turn onto the drum axis — and the place where real geometry beats
	# a box most visibly (chute mouth over funnel mouth).
	var drum : Node3D = ghost.get_node_or_null("ghost_vw_trommel") as Node3D
	if drum == null:
		for c in ghost.get_children():
			if String(c.name).findn("trommel") != -1:
				drum = c as Node3D
				break
	if drum != null:
		var d : Vector3 = drum.global_position
		await _shoot(cam, d + Vector3(14.0, 9.0, 14.0), d + Vector3(0.0, 2.0, 0.0),
			"shot_line1_ghost_drumhead_%s.png" % STAMP)
	else:
		print("[SHOT] WARN: no vw_trommel slot found — skipping the drum-head shot")
		_fails += 1

	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)
