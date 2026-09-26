extends Node
# =============================================================================
# shot_line1_plan — TRUE plan view of the BUILT line 1 (not the ghost).
# =============================================================================
# shot_line1_ghost already renders a straight-down frame, but it shoots the
# placement GHOST — translucent, inert, and framed with a 30 % margin on the
# longer axis, so on a 125 m x 24 m line the machines come out as a pale sliver
# across an empty floor. That is fine for "does the preview render"; it is
# useless for reading the FOLD, which is what the 2026-09-16 head correction
# (feeder -> 90 right -> Westa -> shredder) has to be checked against.
#
# So this tool builds the line for real (_build_full_line, preview = false —
# the same call the operator's placement commits) and shoots it with an
# ORTHOGRAPHIC camera. Orthographic matters: under perspective a 125 m line
# photographed from above has visible parallax, machines at the far ends lean
# outward, and a 90 degree corner does not measure as 90 degrees on the pixels.
# An ortho plan is the one projection where a wrong turn is unmissable.
#
# Run WINDOWED — headless has no rendering device and every frame would be blank:
#   Godot --path . res://src/tests/shot_line1_plan.tscn
#
# Writes into docs/plant/renders/ with line-coded unique names (operator rules
# 2026-07-15 / 2026-07-20), plus a positions JSON next to them so the picture
# can be redrawn or annotated without re-booting the world:
#   shot_line1_plan_full_<stamp>.png  — the whole fold
#   shot_line1_plan_head_<stamp>.png  — the corrected head, feeder -> shredder
#   shot_line1_plan_<stamp>.json      — measured id/pos/size per machine
#
# Both frames go through ShotCommon.check_image_content, so a black or flat
# frame FAILS loudly instead of silently "saving" (audit finding C10).
#
# PROTECT/restore copied from shot_line1_ghost deliberately: booting MainWorld
# against a test slot writes user:// files, and on 2026-09-06 a damaged
# world_layout.json cost a full harness run of misleading reds.
# =============================================================================

const TEST_SLOT : String = "__line1planshot__"
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__line1planshot___save.json",
	"user://__line1planshot___factory.json",
]
const BOOT_FRAMES : int = 120
const OUT_DIR : String = "res://docs/plant/renders/"
const STAMP : String = "2026_09_17"
## Filename stamp for this run: STAMP, or the first user arg
## (`… shot_line1_plan.tscn -- 2026_09_25_v10`), so a series of renders of
## one day does not need the tool edited between runs.
var _stamp : String = STAMP

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

## World-space AABB over every visual part of `nodes`, in GLOBAL coordinates.
## Node origins alone are not enough — a 9 m flotation tank contributes far more
## than its origin — so each MeshInstance3D's own AABB is pushed through that
## mesh's global transform before the union.
## A part more than this far from its own machine's origin is not that machine's
## footprint. The widest thing line 1 places is a 9.5 m extruder, so 40 m is far
## outside anything legitimate while still being an obvious outlier cut.
##
## KEPT, not tightened, after the 2026-09-16 fix. MEASURED on the fixed tree
## (test_macro_part_placement): line 1's worst legitimate part is opzetband_1 at
## 10.5 m, so 40 m has ~30 m of slack and could in principle come down. It is
## deliberately left loose because this constant is NOT the assertion — dropping
## a legitimate part here silently mis-frames a render, which is the worse
## failure. The real invariant is asserted at a per-machine limit of 13-18 m by
## test_macro_part_placement, which is red long before anything reaches 40 m.
const PART_RADIUS_LIMIT_M : float = 40.0

## Meshes rejected by the limit above, as "machine_id/mesh_name" -> world centre.
## Kept and printed rather than silently dropped — see the note in _visual_aabb.
var _orphan_parts : Dictionary = {}

func _visual_aabb(nodes: Array) -> AABB:
	var out := AABB()
	var seeded := false
	for n3 in nodes:
		var root := n3 as Node3D
		if root == null:
			continue
		for n in root.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			if mi == null or mi.mesh == null or not mi.is_visible_in_tree():
				continue
			var world : AABB = mi.global_transform * mi.get_aabb()
			# Reject parts that are nowhere near their own machine.
			#
			# This found a real bug on 2026-09-16: 47 parts across line 1 were
			# pinned at the WORLD ORIGIN instead of on their machines, because
			# AnimatableBody3D.sync_to_physics defaults to TRUE and the line
			# macro moves a machine AFTER the catalog builds it. Including them
			# stretched the measured AABB from 120 m to 269 m and framed this
			# render on empty floor. Fixed at the three construction sites —
			# see the note on src/build/InteractiveHatch.gd.
			#
			# The cut STAYS as a framing guard. One stray part silently ruins
			# every shot this tool takes, and a render is not the place to find
			# that out; test_macro_part_placement is what actually asserts the
			# invariant, and it is red the moment this would trigger. Outliers
			# are reported below, never quietly dropped — if the WARN ever
			# prints again, that test is the thing to run.
			var centre : Vector3 = world.position + world.size * 0.5
			if centre.distance_to(root.global_position) > PART_RADIUS_LIMIT_M:
				_orphan_parts["%s/%s" % [
					String(root.get_meta("placeable_id", root.name)), String(mi.name)]] = centre
				continue
			if not seeded:
				out = world
				seeded = true
			else:
				out = out.merge(world)
	return out

## Shoot straight down over `centre`, ORTHOGRAPHIC, `width_m` metres across.
##
## NOT via look_at: straight down is PARALLEL to the up vector look_at takes,
## which is degenerate — shot_line1_ghost's first attempt came out rolled at an
## arbitrary angle and the line read as a diagonal. The basis is set directly so
## world +X is screen-right and world +Z is screen-down, every time.
func _shoot_plan(cam: Camera3D, centre: Vector3, width_m: float, name_: String) -> bool:
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.keep_aspect = Camera3D.KEEP_WIDTH     # `size` is then the HORIZONTAL span
	cam.size = width_m
	cam.global_position = Vector3(centre.x, 180.0, centre.z)
	cam.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	cam.make_current()
	return await _shoot_current_named(name_, cam)

## Capture whatever the camera already frames, save it, and content-check it.
## Split out of _shoot_plan so the elevation shot — which needs its own basis,
## not a straight-down one — shares the same save + blank-frame guard rather
## than growing a second copy of it.
func _shoot_current_named(name_: String, cam: Camera3D) -> bool:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var outp : String = OUT_DIR + name_
	img.save_png(outp)
	var ok : bool = preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved %s  ortho_size=%.1f m eye=(%.1f, %.1f, %.1f)" % [
		ProjectSettings.globalize_path(outp), cam.size,
		cam.global_position.x, cam.global_position.y, cam.global_position.z])
	if not ok:
		_fails += 1
	return ok

func _ready() -> void:
	print("=== shot_line1_plan — orthographic plan view of the BUILT line 1 ===")
	var user_args : PackedStringArray = OS.get_cmdline_user_args()
	if user_args.size() > 0 and String(user_args[0]) != "":
		_stamp = String(user_args[0])
	print("[SHOT] stamp %s" % _stamp)
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
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var bm : Node = _world.get("build_mode")
	if bm == null:
		print("FATAL: world.build_mode is null"); _finish(1); return

	# Drop it where line 1 actually lives. get_line_start(id, fallback) takes TWO
	# args (WorldLayout.gd:107) — calling it with one throws and aborts the render.
	var wl := get_node_or_null("/root/WorldLayout")
	var start := Vector3(-142.696868896484, 0.0, 42.9187507629395)   # world_layout line_starts["1"]
	if wl != null and wl.has_method("get_line_start"):
		var got = wl.call("get_line_start", "1", start)
		if got is Vector3:
			start = got

	# The real commit path, not a preview: this is what the operator triggers by
	# placing Lijn 1, so the picture is of the object the sim actually runs.
	bm.call("_build_full_line", "line_1", start, 0.0)
	# The operator's placement path rebuilds LineFlow right after the macro
	# (BuildMode, `_active_id.begins_with("line_")`), and the rebuild is what
	# spawns the connectors: chutes, glijgoten and the blower ducts. Without it
	# the render showed none of them (2026-09-25).
	var lf_node : Node = bm.get("line_flow")
	if lf_node != null and lf_node.has_method("rebuild"):
		lf_node.rebuild()
		print("[SHOT] LineFlow rebuilt: connectors spawned")
	else:
		print("[SHOT] WARN: no LineFlow on BuildMode — the render has no connectors")
	await get_tree().process_frame

	# Collect what the macro just placed. Same handle the conformance suite uses
	# (macro_id meta), so the render and the tests are looking at one population.
	var placed : Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("macro_id") and String(n3.get_meta("macro_id")) == "line_1":
			placed.append(n3)
	print("[SHOT] macro placed %d line_1 machines" % placed.size())
	if placed.is_empty():
		print("FATAL: _build_full_line placed nothing tagged macro_id=line_1"); _finish(1); return

	var box : AABB = _visual_aabb(placed)
	print("[SHOT] built visual AABB pos=%s size=%s" % [str(box.position), str(box.size)])
	# A leg extend_machine_legs HID (its path to the floor hit something) is a
	# machine standing on nothing, and a plan view cannot show it. Report each
	# one with what its ray hits (2026-09-25: the tank's inlet cyclones lost
	# theirs when the tank moved).
	await get_tree().physics_frame
	var space := (placed[0] as Node3D).get_world_3d().direct_space_state
	var hidden_legs := 0
	for n3 in placed:
		var node := n3 as Node3D
		for m in node.find_children("*", "MeshInstance3D", true, false):
			var leg := m as MeshInstance3D
			if leg == null or not leg.is_in_group("machine_leg") or leg.visible:
				continue
			hidden_legs += 1
			var lp : Vector3 = leg.global_position
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(lp.x, node.global_position.y + 0.05, lp.z), Vector3(lp.x, -0.05, lp.z))
			if node is CollisionObject3D:
				q.exclude = [(node as CollisionObject3D).get_rid()]
			var hit := space.intersect_ray(q)
			var what : String = "nothing now"
			if not hit.is_empty():
				var col := hit["collider"] as Node
				what = "%s at y %.2f" % [str(col.get_path()) if col != null else "?", (hit["position"] as Vector3).y]
			print("[SHOT] hidden leg: %s #%d at (%.2f, %.2f) -> %s" % [
				String(node.get_meta("placeable_id", "")), int(node.get_meta("macro_index", -1)), lp.x, lp.z, what])
	print("[SHOT] %d hidden machine leg(s)" % hidden_legs)
	if not _orphan_parts.is_empty():
		print("[SHOT] WARN: %d part(s) resolve >%.0f m from their own machine and were"
			% [_orphan_parts.size(), PART_RADIUS_LIMIT_M])
		print("[SHOT]       excluded from the framing — see the note in _visual_aabb.")
		var shown := 0
		for k in _orphan_parts:
			print("[SHOT]       %-40s at %s" % [k, str(_orphan_parts[k])])
			shown += 1
			if shown >= 8:
				print("[SHOT]       ... and %d more" % (_orphan_parts.size() - shown))
				break

	# Dump measured geometry beside the PNGs, so the plan can be re-drawn or
	# annotated later without booting the world again.
	# Read each machine's LEG from the macro's own macro_anchor meta
	# (BuildMode.gd:2429 stamps {start, rot_y} per leg), not from the shape of
	# the walk. Inferring legs by differencing consecutive positions cannot work
	# here: line 1 lays several stations as side-by-side PAIRS, so the walk
	# zigzags, and the laser-filter lump carts are furniture placed beside leg 7
	# rather than a leg of their own — a differencing pass reports them as two
	# extra legs and merges the two real head legs into one. The anchor is the
	# macro's own answer, so it cannot disagree with what was built.
	var dump : Array = []
	for n3 in placed:
		var node := n3 as Node3D
		var b : AABB = _visual_aabb([node])
		var anchor : Dictionary = node.get_meta("macro_anchor", {}) as Dictionary
		dump.append({
			"id": String(node.get_meta("placeable_id", node.name)),
			"name": String(node.name),
			"macro_index": int(node.get_meta("macro_index", -1)),
			"leg_rot_y_deg": rad_to_deg(float(anchor.get("rot_y", 0.0))) if not anchor.is_empty() else null,
			"leg_start": [anchor["start"].x, anchor["start"].y, anchor["start"].z] if anchor.has("start") else null,
			"pos": [node.global_position.x, node.global_position.y, node.global_position.z],
			"rot_y_deg": rad_to_deg(node.global_rotation.y),
			"aabb_pos": [b.position.x, b.position.y, b.position.z],
			"aabb_size": [b.size.x, b.size.y, b.size.z],
		})
		# The drum's walkway stair, measured on its own (the operator places it
		# against the dewatering screw, 2026-09-25).
		var fs : Node = node.find_child("FloorStair", true, false)
		if fs != null and fs is Node3D:
			var sb2 : AABB = _visual_aabb([fs])
			(dump[dump.size() - 1] as Dictionary)["stair_aabb_pos"] = [sb2.position.x, sb2.position.y, sb2.position.z]
			(dump[dump.size() - 1] as Dictionary)["stair_aabb_size"] = [sb2.size.x, sb2.size.y, sb2.size.z]
	dump.sort_custom(func(a, c): return int(a["macro_index"]) < int(c["macro_index"]))
	var jf := FileAccess.open(OUT_DIR + "shot_line1_plan_%s.json" % _stamp, FileAccess.WRITE)
	jf.store_string(JSON.stringify({"start": [start.x, start.y, start.z], "machines": dump}, "  "))
	jf.close()
	print("[SHOT] wrote %s" % ProjectSettings.globalize_path(OUT_DIR + "shot_line1_plan_%s.json" % _stamp))

	# Line 1 lives indoors, so the shell has to come off or the shot is of a roof,
	# and the HUD covers a third of the frame. Both hidden for the capture only —
	# this scene is torn down in _finish, nothing is saved.
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
	# The overhead TL light fixtures hang at 4-10 m under the (hidden) roof. From
	# straight above they read as thin diagonal bars across the floor plan, and
	# the operator asked what those shapes were (2026-09-25). They are not floor
	# equipment, so plan views leave them out.
	var lights : Node = _world.find_child("OverheadLights", true, false)
	if lights != null and lights is Node3D:
		(lights as Node3D).visible = false
		print("[SHOT] OverheadLights hidden for the capture (%d fixtures)" % lights.get_child_count())
	await get_tree().process_frame

	# In-game clock is 07:00 (Vroege dienst) — the world sun is barely up and the
	# first captures came out too murky to read grey machines against a brown
	# floor. Add a capture light rather than fight the day/night cycle. Straight
	# down-ish, so a plan view gets flat even lighting instead of long shadows
	# that read as machines that are not there.
	var key := DirectionalLight3D.new()
	key.light_energy = 1.35
	key.shadow_enabled = false
	add_child(key)
	key.global_position = box.position + box.size * 0.5 + Vector3(0.0, 90.0, 0.0)
	key.rotation_degrees = Vector3(-72.0, -30.0, 0.0)

	var cam := Camera3D.new()
	cam.far = 4000.0
	add_child(cam)

	# ── full: the whole fold, tight ─────────────────────────────────────────
	# 6 % margin, not shot_line1_ghost's 30 %: the line is 5:1, so every extra
	# percent of horizontal margin costs five times as much dead floor.
	var centre : Vector3 = box.position + box.size * 0.5
	await _shoot_plan(cam, centre, box.size.x * 1.06,
		"shot_line1_plan_full_%s.png" % _stamp)

	# ── head: the corrected feeder -> Westa -> shredder corner ──────────────
	# The 2026-09-16 fold correction is entirely in these three machines, and at
	# full-line scale they are ~25 px wide. Frame them on their own AABB so the
	# right-hand turn is actually legible.
	var head : Array = []
	for n3 in placed:
		var node := n3 as Node3D
		if String(node.get_meta("placeable_id", "")) in [
				"opzetband_1", "westa_band_1", "shredder_1", "transport_belt", "uitvoerband_1"]:
			head.append(node)
	if head.is_empty():
		print("[SHOT] WARN: no head machines found — skipping the head shot")
		_fails += 1
	else:
		var hb : AABB = _visual_aabb(head)
		var hc : Vector3 = hb.position + hb.size * 0.5
		print("[SHOT] head AABB pos=%s size=%s" % [str(hb.position), str(hb.size)])
		await _shoot_plan(cam, hc, maxf(hb.size.x, hb.size.z * 1.78) * 1.30,
			"shot_line1_plan_head_%s.png" % _stamp)

	# ── elevation: the overband magnet over the uitvoerband ─────────────────
	# A plan view cannot show a HEIGHT, and the 2026-09-17 change is entirely a
	# height: the uitvoerband was raised 0.281 m and its rails cut to a skirt
	# board so the magnet clears the deck by 0.25 m. Shot from the side, along
	# the belt's cross axis, orthographic for the same reason the plans are —
	# under perspective a clearance measured off the pixels is worth nothing.
	var magnet : Node3D = null
	var belts : Array = []
	for n3 in placed:
		var node := n3 as Node3D
		# Line 1's cross-belt magnet over uitvoerband_1 since 2026-09-25.
		match String(node.get_meta("placeable_id", "")):
			"overband_magnet", "overband_magnet_l1":
				magnet = node
			"transport_belt", "uitvoerband_1":
				belts.append(node)
	# Resolve the uitvoerband AFTER the walk — it is whichever belt the magnet
	# straddles, and picking it inside the loop would depend on whether the
	# magnet happened to be visited first.
	var uitvoer : Node3D = null
	if magnet != null:
		var nearest := INF
		for b in belts:
			var d : float = (b as Node3D).global_position.distance_to(magnet.global_position)
			if d < nearest:
				nearest = d
				uitvoer = b as Node3D
	if magnet == null:
		print("[SHOT] WARN: no overband_magnet found — skipping the elevation shot")
		_fails += 1
	else:
		var eb : AABB = _visual_aabb([magnet, uitvoer] if uitvoer != null else [magnet])
		var ec : Vector3 = eb.position + eb.size * 0.5
		# Look along -Z from in front of the pair. NOT via look_at — a level
		# elevation wants an exact basis, and look_at would roll it off any
		# residual offset between the two machines' centres.
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		cam.size = maxf(eb.size.x, eb.size.y * 1.78) * 1.45
		const EYE_DIST : float = 40.0
		cam.global_position = Vector3(ec.x, ec.y, ec.z + EYE_DIST)
		cam.rotation = Vector3.ZERO
		# An elevation looks THROUGH the plant rather than down at it, and the
		# first two attempts both came back with a translucent blue placard
		# filling the frame. Near/far clipping was not enough (the thinnest slab
		# containing the magnet also contains its neighbours), and hiding the
		# other MACRO machines was not either — the obstruction is world
		# furniture, not a line-1 machine, and enumerating every candidate is a
		# guessing game.
		#
		# So isolate by RENDER LAYER instead, which is exact and does not care
		# what the obstruction is or where it sits: put this shot's two machines
		# on a private layer and cull the camera to it. Layers are restored below,
		# so nothing leaks into a later shot.
		const ELEV_LAYER : int = 1 << 19
		var saved_layers : Dictionary = {}
		for subject in [magnet, uitvoer]:
			if subject == null:
				continue
			for m in (subject as Node3D).find_children("*", "VisualInstance3D", true, false):
				var vi := m as VisualInstance3D
				if vi == null:
					continue
				saved_layers[vi] = vi.layers
				vi.layers = ELEV_LAYER
		cam.cull_mask = ELEV_LAYER
		print("[SHOT] elevation isolated to %d mesh(es) on a private render layer"
			% saved_layers.size())
		# The plan shots' key light comes in steeply from above, which is right for
		# a view looking straight DOWN and useless for one looking sideways: the
		# first isolated elevation came out as a silhouette against the dawn sky,
		# because every surface facing the camera was in shadow. Add a fill along
		# the view direction for this frame only.
		var fill := DirectionalLight3D.new()
		fill.light_energy = 2.6
		fill.shadow_enabled = false
		# A Light3D IS a VisualInstance3D, so the camera's cull_mask culls the
		# LIGHT as well as the geometry. The first fill was added on the default
		# layer and changed the frame's mean luminance by 0.0001 — it was being
		# culled out entirely. It has to sit on the same private layer as the
		# subject to light it.
		fill.layers = ELEV_LAYER
		add_child(fill)
		fill.rotation_degrees = Vector3(-18.0, 0.0, 0.0)   # shines along -Z, slightly down
		cam.make_current()
		print("[SHOT] elevation AABB pos=%s size=%s" % [str(eb.position), str(eb.size)])
		await _shoot_current_named("shot_line1_elevation_magnet_%s.png" % _stamp, cam)
		for vi in saved_layers:
			(vi as VisualInstance3D).layers = saved_layers[vi]
		cam.cull_mask = 0xFFFFF
		fill.queue_free()

	# ── wet street: drum → scheidingsgoot → friction/dryer pairs → blowers → mill ─
	# Added 2026-09-25 for the operator's "flush" corrections to this stretch. A
	# plan view, and a side view along the flow, isolated on a private layer like
	# the magnet elevation above but by REGION: every visual whose centre lies in
	# the stretch's box, so LineFlow's connectors (the glijgoot chutes, the ducts)
	# are in the frame too.
	var street : Array = []
	var i_drum := -1
	var i_mill := -1
	for n3 in placed:
		var node := n3 as Node3D
		var pid := String(node.get_meta("placeable_id", ""))
		var mi_ := int(node.get_meta("macro_index", -1))
		if pid == "vw_trommel":
			i_drum = mi_
		elif pid == "mill" and (i_mill < 0 or mi_ < i_mill):
			i_mill = mi_
	var drum : Node3D = null
	for n3 in placed:
		var node := n3 as Node3D
		var mi_ := int(node.get_meta("macro_index", -1))
		if i_drum >= 0 and i_mill >= 0 and mi_ >= i_drum and mi_ <= i_mill:
			street.append(node)
			if mi_ == i_drum:
				drum = node
	if street.is_empty() or drum == null:
		print("[SHOT] WARN: no drum..mill stretch found — skipping the wet-street shots")
		_fails += 1
	else:
		var sb : AABB = _visual_aabb(street)
		var sc : Vector3 = sb.position + sb.size * 0.5
		print("[SHOT] wet street AABB pos=%s size=%s (%d machines)" % [str(sb.position), str(sb.size), street.size()])
		cam.cull_mask = 0xFFFFF
		await _shoot_plan(cam, sc, maxf(sb.size.x, sb.size.z * 1.78) * 1.12,
			"shot_line1_plan_wetstreet_%s.png" % _stamp)
		# Side view: look across the flow, from the drum's walkway side.
		var fwd : Vector3 = drum.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side : Vector3 = Vector3(-fwd.z, 0.0, fwd.x)
		const SIDE_LAYER : int = 1 << 18
		# The stretch's own machines, plus LineFlow's connectors (the chutes and
		# ducts between them) inside its box. A plain region test also pulled in
		# the tank and its screws behind the street.
		var region : AABB = sb.grow(0.5)
		var saved : Dictionary = {}
		var candidates : Array = []
		for node in street:
			candidates.append_array((node as Node).find_children("*", "VisualInstance3D", true, false))
		var conns : Node = _world.find_child("Connectors", true, false)
		if conns != null:
			for m in conns.find_children("*", "VisualInstance3D", true, false):
				var cvi := m as VisualInstance3D
				var cwb : AABB = cvi.global_transform * cvi.get_aabb()
				if region.has_point(cwb.position + cwb.size * 0.5):
					candidates.append(cvi)
		for m in candidates:
			var vi := m as VisualInstance3D
			if vi == null or vi is Light3D or not vi.is_visible_in_tree():
				continue
			saved[vi] = vi.layers
			vi.layers = SIDE_LAYER
		var side_fill := DirectionalLight3D.new()
		side_fill.light_energy = 2.4
		side_fill.shadow_enabled = false
		side_fill.layers = SIDE_LAYER
		add_child(side_fill)
		side_fill.global_transform = Transform3D(
			Basis(Vector3.UP.cross(side).normalized(), Vector3.UP, side).rotated(
				Vector3.UP.cross(side).normalized(), deg_to_rad(-18.0)), sc)
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.keep_aspect = Camera3D.KEEP_WIDTH
		var along : float = absf(sb.size.x * fwd.x) + absf(sb.size.z * fwd.z)
		cam.size = maxf(along, sb.size.y * 1.78) * 1.08
		cam.global_transform = Transform3D(
			Basis(Vector3.UP.cross(side).normalized(), Vector3.UP, side),
			Vector3(sc.x, sb.position.y + sb.size.y * 0.5, sc.z) + side * 60.0)
		cam.cull_mask = SIDE_LAYER
		cam.make_current()
		print("[SHOT] wet street side view: %d visual(s) on a private layer" % saved.size())
		await _shoot_current_named("shot_line1_side_wetstreet_%s.png" % _stamp, cam)
		for vi in saved:
			(vi as VisualInstance3D).layers = saved[vi]
		cam.cull_mask = 0xFFFFF
		side_fill.queue_free()

	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)
