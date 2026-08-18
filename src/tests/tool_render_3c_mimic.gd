extends Node
## TOOL — renders the Line 3C machine mimic for the HMI overview screen.
##
## The operator's real Waslijn 3C Overzicht (photos IMG-20240811-WA0009/10) is
## ~80% an isometric drawing of the line; the Claude-Design export reproduced
## only the labels and value boxes, so the in-game screen looked empty. Rather
## than hand-draw the mimic, this renders the SIM'S OWN line-3C machines — the
## same 21 placeables the player walks past, in the same flow order, carrying
## the same L3C codes the screen labels use.
##
## Outputs (into docs/plant/hmi_screens_2026-07-26/mimic/):
##   <screen>.png          — transparent-background orthographic render
##   <screen>.json        — {code: {x, y}} in mimic-pixel space, so the HTML can
##                          anchor each value box to its machine instead of
##                          hard-coding pixels that drift when the line moves.
##
## Run WINDOWED (needs a real renderer — headless produces an empty texture):
##   godot --path . res://src/tests/tool_render_3c_mimic.tscn

const SRC_SLOT   := "save1"
const TOOL_SLOT  := "mimictool"
const OUT_DIR    := "res://docs/plant/hmi_screens_2026-07-26/mimic/"
## Outputs are named after the SCREEN they belong to, so hmi_shell.html can
## find a mimic by convention (mimic/<screen basename>.png/.json) with no
## mapping table to keep in sync.
const SCREEN_BASE := "Waslijn 3C Overzicht"

## The design's equipment area: 1280 wide, 800 - 92 (header) - 44 (nav) tall.
const MIMIC_W : int = 1280
const MIMIC_H : int = 664

## Isometric-ish framing, matched by eye to the operator's photo: line running
## left→right, viewed from above and slightly in front.
const ELEV_DEG : float = 28.0
const YAW_OFF_DEG : float = 18.0    # swing off perpendicular so depth reads
const FIT_MARGIN : float = 1.06

## BANDS — the operator's screen is NOT one straight run (photo
## IMG-20240811-WA0010). The wash line cascades left→right across the top, and
## after L3C.15 (Transport Ventilator, a PNEUMATIC blower) the material is blown
## back to the bottom-left, where the plasmaq / extruder-silo / rondmeng cluster
## is drawn as its own group. The sim places all 20 machines in one physical
## line, so a single render can never reproduce that arrangement — each band is
## framed and rendered separately, then composited into the destination rect the
## panel uses. Rects are in mimic-canvas pixels (1280 x 664).
const BANDS : Array = [
	{
		"name":  "wash",
		"codes": ["L3C.1", "L3C.3", "L3C.4L", "L3C.4R", "L3C.5L", "L3C.5R", "L3C.6",
				  "L3C.9L", "L3C.9R", "L3C.10L", "L3C.10R", "L3C.11", "L3C.12",
				  "L3C.13", "L3C.14L", "L3C.14R", "L3C.15"],
		"rect":  Rect2i(10, 0, 1260, 430),
	},
	{
		"name":  "extruder",
		"codes": ["L3C.16", "L3C.18", "L3C.19"],
		"rect":  Rect2i(90, 396, 660, 268),
	},
]

## Dedicated visual layer so the mimic camera sees ONLY the line-3C machines —
## no building shell, no floor, no other lines. Layers are restored afterwards.
const MIMIC_LAYER_BIT : int = 19

var _world : Node3D = null
var _restore : Array = []   # [[MeshInstance3D, old_layers], ...]

func _ready() -> void:
	print("[MIMIC] boot")
	for suffix in ["_factory.json", "_save.json"]:
		var s := "user://%s%s" % [SRC_SLOT, suffix]
		var d := "user://%s%s" % [TOOL_SLOT, suffix]
		if FileAccess.file_exists(s):
			DirAccess.copy_absolute(s, d)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TOOL_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("[MIMIC] FAIL MainWorld.tscn"); get_tree().quit(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world

	# Wait for the save's line_3c machines to exist.
	var nodes : Array = []
	var waited := 0.0
	while waited < 120.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
		nodes = _line3c_nodes()
		if nodes.size() >= 20:
			break
	print("[MIMIC] line_3c nodes found: %d" % nodes.size())
	if nodes.is_empty():
		print("[MIMIC] FAIL no line_3c machines in %s" % SRC_SLOT)
		get_tree().quit(3); return
	# Let physics/props settle so nothing is mid-spawn in the render.
	var settle := 0.0
	while settle < 3.0:
		await get_tree().process_frame
		settle += get_process_delta_time()

	# Flat, even lighting on the mimic layer only. The machines sit INSIDE the
	# building, so the plant's own lights leave them near-black silhouettes
	# (measured on the first run) — and the operator's real mimic is flat CAD
	# artwork anyway, not a lit photograph. light_cull_mask keeps this off the
	# rest of the world, which the tool must not disturb.
	var key := DirectionalLight3D.new()
	key.light_cull_mask = 1 << MIMIC_LAYER_BIT
	key.shadow_enabled = false
	key.light_energy = 1.1
	add_child(key)
	key.global_rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-35.0), 0.0)

	# ── render each band, composite into one canvas ─────────────────────────
	var canvas := Image.create(MIMIC_W, MIMIC_H, false, Image.FORMAT_RGBA8)
	canvas.fill(Color(0, 0, 0, 0))
	var anchors := {}
	for band in BANDS:
		var subset : Array = []
		for e in nodes:
			if String(e["code"]) in (band["codes"] as Array):
				subset.append(e)
		if subset.is_empty():
			print("[MIMIC] band '%s' has no machines — skipped" % String(band["name"]))
			continue
		var rect : Rect2i = band["rect"]
		var res : Dictionary = await _render_band(subset, rect.size)
		var band_img : Image = res["image"]
		# blend, not blit: bands may overlap slightly and each carries alpha.
		canvas.blend_rect(band_img, Rect2i(Vector2i.ZERO, rect.size), rect.position)
		for code in (res["anchors"] as Dictionary):
			var p : Vector2 = (res["anchors"] as Dictionary)[code]
			anchors[code] = {"x": snappedf(p.x + rect.position.x, 0.1),
							 "y": snappedf(p.y + rect.position.y, 0.1)}
		print("[MIMIC] band '%s': %d machine(s) into %s" % [String(band["name"]), subset.size(), str(rect)])

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var png_path := OUT_DIR + SCREEN_BASE + ".png"
	var err := canvas.save_png(ProjectSettings.globalize_path(png_path))
	print("[MIMIC] png %s (err %d, %dx%d)" % [png_path, err, canvas.get_width(), canvas.get_height()])

	var f := FileAccess.open(OUT_DIR + SCREEN_BASE + ".json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"generated_from": SRC_SLOT,
			"mimic_size": [MIMIC_W, MIMIC_H],
			"note": "x,y are pixel coords inside the screen's equipment area (top:92px).",
			"anchors": anchors,
		}, "\t"))
		f.close()
	print("[MIMIC] anchors: %d codes" % anchors.size())
	for code in anchors:
		print("   %-8s -> (%6.1f, %6.1f)" % [code, anchors[code]["x"], anchors[code]["y"]])

	_restore_layers()
	print("[MIMIC] done")
	get_tree().quit(0)

# ── helpers ────────────────────────────────────────────────────────────────

## Render ONE band of machines into an image of `size`, and report where each
## machine landed inside it. Each band gets its own camera + framing, which is
## what lets the wash line and the extruder cluster be arranged the way the
## operator's panel arranges them rather than as one physical row.
func _render_band(subset: Array, size: Vector2i) -> Dictionary:
	# Tag ONLY this band's machines onto the mimic layer. Tagging all 20 up
	# front and merely re-framing per band does not exclude anything: every
	# band camera shares the layer, so wash-line machines standing inside the
	# extruder band's frame were rendered into it as unlabelled strays
	# (measured — a grey box appeared bottom-left with no code).
	_tag_layers(subset)
	var sv := SubViewport.new()
	sv.size = size
	sv.transparent_bg = true          # the HMI's own dark background shows through
	sv.own_world_3d = false
	sv.world_3d = _world.get_world_3d()
	sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(sv)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.cull_mask = 1 << MIMIC_LAYER_BIT
	cam.near = 0.05
	cam.far = 4000.0
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.35
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	sv.add_child(cam)
	cam.current = true

	_frame(cam, subset, float(size.x) / float(size.y))
	for _i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw

	var img : Image = sv.get_texture().get_image()
	var anchors := {}
	for e in subset:
		anchors[String(e["code"])] = cam.unproject_position(_visual_centre(e["node"]))
	sv.queue_free()
	_restore_layers()
	return {"image": img, "anchors": anchors}

## Placed line_3c machines with their plant codes, ordered by macro_index.
func _line3c_nodes() -> Array:
	var out : Array = []
	for n in get_tree().get_nodes_in_group("placed_object"):
		if not (n is Node3D) or not n.has_meta("macro_id"):
			continue
		if String(n.get_meta("macro_id")) != "line_3c":
			continue
		var idx := int(n.get_meta("macro_index")) if n.has_meta("macro_index") else -1
		var code := Line3CDef.code_for_macro_entry("line_3c", idx)
		if code == "" or code.begins_with("C") or code in ["PCU", "Extr", "Laser", "Degas",
				"Melt", "Kop", "Heet", "Ontw", "Centr", "Weeg", "Voorraad"]:
			continue   # wash-line units only — the extruder back-end is a separate screen
		out.append({"node": n, "code": code, "idx": idx})
	out.sort_custom(func(a, b): return int(a["idx"]) < int(b["idx"]))
	return out

## Centre of a machine's visible geometry (not its origin, which often sits on
## the floor — a value box anchored there would float under the machine).
func _visual_centre(n: Node3D) -> Vector3:
	var acc := AABB()
	var got := false
	for m in _sane_meshes(n):
		var world_aabb : AABB = m.global_transform * m.get_aabb()
		if not got:
			acc = world_aabb; got = true
		else:
			acc = acc.merge(world_aabb)
	return acc.get_center() if got else n.global_position

func _meshes(n: Node) -> Array:
	var out : Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_meshes(c))
	return out

## Any single mesh wider than this is treated as a broken bounding box and left
## out of the framing maths. MEASURED 2026-08-10: L3C.18 (Extruder Silo, the
## `silo` placeable) reports a 215 m world AABB while every other line-3C
## machine is 1.2-15.7 m; including it stretched the frame from 72 m to 281 m
## and rendered the whole line into a quarter of the image. Offenders are
## printed by name so the underlying model can be fixed.
const MAX_MESH_M : float = 60.0
## A mesh belonging to a machine must sit near that machine. MEASURED: L3C.18's
## 215 m span is NOT one oversized mesh (a size filter alone caught nothing) —
## it is a normally-sized child mesh PARENTED to the silo but positioned ~210 m
## away, so only a locality test finds it.
const MAX_MESH_DIST_M : float = 30.0
var _reported_giants : Dictionary = {}

## Meshes that genuinely belong to `owner` — believable size AND near it.
func _sane_meshes(owner: Node) -> Array:
	var out : Array = []
	var origin : Vector3 = (owner as Node3D).global_position if owner is Node3D else Vector3.ZERO
	for m in _meshes(owner):
		var mi : MeshInstance3D = m
		var wa : AABB = mi.global_transform * mi.get_aabb()
		var too_big : bool = wa.size.x > MAX_MESH_M or wa.size.y > MAX_MESH_M or wa.size.z > MAX_MESH_M
		var dist : float = wa.get_center().distance_to(origin)
		if too_big or dist > MAX_MESH_DIST_M:
			var key := String(mi.get_path())
			if not _reported_giants.has(key):
				_reported_giants[key] = true
				print("[MIMIC] STRAY MESH ignored: %s\n           aabb=%.1f x %.1f x %.1f m, %.1f m from its machine's origin"
					% [key, wa.size.x, wa.size.y, wa.size.z, dist])
			continue
		out.append(mi)
	return out

func _tag_layers(nodes: Array) -> void:
	for e in nodes:
		for m in _meshes(e["node"]):
			var mi : MeshInstance3D = m
			_restore.append([mi, mi.layers])
			mi.layers = mi.layers | (1 << MIMIC_LAYER_BIT)
	print("[MIMIC] tagged %d mesh(es) onto the mimic layer" % _restore.size())

func _restore_layers() -> void:
	for pair in _restore:
		var mi : MeshInstance3D = pair[0]
		if is_instance_valid(mi):
			mi.layers = int(pair[1])
	_restore.clear()   # per-band tagging: never restore a stale snapshot twice

func _bounds(nodes: Array) -> AABB:
	var acc := AABB()
	var got := false
	for e in nodes:
		for m in _sane_meshes(e["node"]):
			var wa : AABB = m.global_transform * m.get_aabb()
			if not got:
				acc = wa; got = true
			else:
				acc = acc.merge(wa)
	return acc

## Aim + frame the line in ONE analytic pass.
##
## The first version iterated (measure pixels -> rescale cam.size -> repeat) and
## did not converge: the line came out tiny and jammed against the right edge.
## Projecting every mesh-AABB corner onto the camera's own right/up axes solves
## the framing exactly instead of hunting for it — no feedback loop to diverge.
func _frame(cam: Camera3D, nodes: Array, aspect: float) -> void:
	var first : Vector3 = (nodes[0]["node"] as Node3D).global_position
	var last  : Vector3 = (nodes[nodes.size() - 1]["node"] as Node3D).global_position
	var axis := last - first
	axis.y = 0.0
	if axis.length() < 0.01:
		axis = Vector3.RIGHT
	axis = axis.normalized()
	# Perpendicular in plan, swung by YAW_OFF so the machines are not seen
	# perfectly side-on (the operator's mimic shows depth).
	var perp := Vector3(axis.z, 0.0, -axis.x).rotated(Vector3.UP, deg_to_rad(YAW_OFF_DEG))
	var elev := deg_to_rad(ELEV_DEG)
	var fwd := (-perp * cos(elev) - Vector3.UP * sin(elev)).normalized()
	var right := fwd.cross(Vector3.UP).normalized()
	if right.dot(axis) < 0.0:
		right = -right          # keep the line reading left -> right, as on the panel
	var up := right.cross(fwd).normalized()

	# Extents of every machine corner along the camera's own axes.
	var u_lo := INF; var u_hi := -INF
	var v_lo := INF; var v_hi := -INF
	var w_lo := INF
	for e in nodes:
		for m in _sane_meshes(e["node"]):
			var wa : AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			for i in range(8):
				var p : Vector3 = wa.get_endpoint(i)
				var u := p.dot(right); var v := p.dot(up); var w := p.dot(fwd)
				u_lo = minf(u_lo, u); u_hi = maxf(u_hi, u)
				v_lo = minf(v_lo, v); v_hi = maxf(v_hi, v)
				w_lo = minf(w_lo, w)
	# Diagnostic: an outlier AABB silently blows the framing out (first analytic
	# run framed the line into ~300 px of 1280). Report the per-machine spans so
	# the culprit is visible instead of guessed at.
	print("[MIMIC] camera-space extents: u %.1f..%.1f (%.1f m), v %.1f..%.1f (%.1f m)"
		% [u_lo, u_hi, u_hi - u_lo, v_lo, v_hi, v_hi - v_lo])
	for e in nodes:
		var nu_lo := INF; var nu_hi := -INF; var nv_lo := INF; var nv_hi := -INF
		for m in _sane_meshes(e["node"]):
			var na : AABB = (m as MeshInstance3D).global_transform * (m as MeshInstance3D).get_aabb()
			for i in range(8):
				var q : Vector3 = na.get_endpoint(i)
				nu_lo = minf(nu_lo, q.dot(right)); nu_hi = maxf(nu_hi, q.dot(right))
				nv_lo = minf(nv_lo, q.dot(up));    nv_hi = maxf(nv_hi, q.dot(up))
		print("   %-8s u %8.1f..%8.1f (%6.1f m)  v %8.1f..%8.1f (%6.1f m)"
			% [String(e["code"]), nu_lo, nu_hi, nu_hi - nu_lo, nv_lo, nv_hi, nv_hi - nv_lo])

	# Camera3D.size is the VERTICAL extent (keep_aspect defaults to KEEP_HEIGHT).
	cam.size = maxf(v_hi - v_lo, (u_hi - u_lo) / aspect) * FIT_MARGIN
	cam.global_transform = Transform3D(
		Basis(right, up, -fwd),
		right * ((u_lo + u_hi) * 0.5) + up * ((v_lo + v_hi) * 0.5) + fwd * (w_lo - 200.0))
