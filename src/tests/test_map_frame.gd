extends Node
# =============================================================================
# HEADLESS INVARIANT TEST — site-map frame (MapOverlay projection).
#
# Guards the 2026-07-20 fix that removed the last surviving copy of the
# hand-baked BF->PC affine (MapOverlay _BF_PC_O/_X/_Z): the building outline
# was displaced by (surveyed-anchor - actual-anchor), so the operator stood
# physically inside the shell while the map drew them outside the rectangle.
# The outline is now placed via InteriorLightingManager's MEASURED building
# frame and projected through the SAME _to_px as every entity layer.
#
# Invariants asserted (pure px-space math on the overlay's own functions —
# no screenshot pixel reading):
#   (a) player at the shell-outline interior centroid -> the You marker
#       (panel centre by construction) lies INSIDE the drawn outline polygon;
#   (b) a vehicle parked at the player's position projects to the SAME px as
#       the You marker (shared canonical projection);
#   (c) the outline px polygon is non-degenerate AND its area maps back
#       through scale_px to the _BF_OUTLINE shape's known area (the px
#       mapping must be rigid: rotation + uniform scale only).
#
#   GODOT --headless --path . res://src/tests/test_map_frame.tscn
# =============================================================================

const TEST_SLOT := "__mapframe__"
const BOOT_FRAMES := 80            # same settle window as repro_clamp_spawn
const FIT_WAIT_FRAMES := 1200      # ILM waits <=300 frames for Plant + physics
                                   # warm-up before fitting; 20 s is ample
const PX_EPS := 0.01               # projection identity tolerance (px)
const AREA_REL_TOL := 0.05         # rigid mapping: <=5% area drift allowed

const PROTECT := [
	"user://world_layout.json",
	"user://__mapframe___save.json",
	"user://__mapframe___factory.json",
]

var _backups : Dictionary = {}

func _ready() -> void:
	print("=== TEST — map frame invariants (MapOverlay canonical projection) ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	_backup_files()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _restore_files(); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var mw := world as MainWorld
	if mw == null or mw.player == null:
		print("FATAL: MainWorld/player missing after boot"); _finish(world, 2); return

	# A standalone overlay instance wired exactly like HUD wires it — the test
	# exercises MapOverlay's own code, not a mock.
	var overlay := MapOverlay.new()
	overlay.main_world = mw
	get_tree().root.add_child(overlay)

	# The outline exists only once ILM's measured fit lands (it awaits Plant
	# init + physics frames). Poll; a world WITH a shell MUST produce a fit.
	var waited := 0
	while overlay._outline_scene_pts().size() < 3 and waited < FIT_WAIT_FRAMES:
		waited += 1
		await get_tree().process_frame
	var scene_poly := overlay._outline_scene_pts()
	if scene_poly.size() < 3:
		print("  FAIL  : measured building frame never became available (ILM fit missing after %d frames)" % waited)
		_finish(world, 1); return
	print("  ok    : measured outline available after %d frames (%d verts)" % [waited, scene_poly.size()])

	var fails := 0

	# ── (a) player at shell interior centroid -> You marker inside outline ────
	var centroid := _poly_centroid(scene_poly)
	if not Geometry2D.is_point_in_polygon(centroid, scene_poly):
		fails += 1
		print("  FAIL  : precondition — polygon centroid %s not inside the scene outline" % str(centroid))
	mw.player.global_position = Vector3(centroid.x, mw.player.global_position.y, centroid.y)
	# open() caches the north-up yaw exactly like the live M-key path; all
	# assertions below run synchronously after the teleport (no frames in
	# between) so physics cannot move the player under the measurement.
	overlay.open()
	var vparams : Dictionary = overlay.view_params()
	var panel : Rect2 = vparams["panel"]
	var center_px : Vector2 = vparams["center_px"]
	var scale_px : float = vparams["scale_px"]
	var origin : Vector2 = vparams["origin"]
	if scale_px <= 0.0 or panel.size.x <= 0.0:
		print("  FAIL  : degenerate view (panel=%s scale_px=%.4f) — viewport size broken headless?" % [str(panel), scale_px])
		_finish(world, 1); return
	var opx := overlay.outline_px(center_px, scale_px, origin)
	if opx.size() < 3:
		fails += 1
		print("  FAIL  : outline_px empty despite a fitted frame")
	elif Geometry2D.is_point_in_polygon(center_px, opx):
		print("  ok    : You marker (panel centre) inside the outline with player at the shell centroid")
	else:
		fails += 1
		print("  FAIL  : You marker %s OUTSIDE outline polygon — the operator-inside/map-outside bug" % str(center_px))

	# ── (b) vehicle at the player's position projects onto the You marker ────
	var veh : Node3D = null
	for c in mw.get_children():
		if c is BaseVehicle:
			veh = c
			break
	if veh == null:
		# No vehicle in this world: a plain Node3D still goes through the
		# identical _to_px call the vehicle layer uses, so the invariant holds.
		veh = Node3D.new()
		mw.add_child(veh)
	veh.global_position = mw.player.global_position
	var vpx : Vector2 = overlay._to_px(veh.global_position, center_px, scale_px, origin)
	if vpx.distance_to(center_px) <= PX_EPS:
		print("  ok    : vehicle at player position projects onto the You marker (d=%.4f px, node=%s)" % [vpx.distance_to(center_px), veh.name])
	else:
		fails += 1
		print("  FAIL  : vehicle at player position projects %.3f px away from the You marker" % vpx.distance_to(center_px))

	# ── (c) outline px polygon non-degenerate + rigid-mapping area check ──────
	var area_px : float = absf(_shoelace(opx))
	var expected_m2 : float = absf(_shoelace(PackedVector2Array(MapOverlay._BF_OUTLINE)))
	if area_px < 100.0:
		fails += 1
		print("  FAIL  : outline px area %.1f px^2 — degenerate polygon" % area_px)
	else:
		var area_m2 : float = area_px / (scale_px * scale_px)
		if absf(area_m2 - expected_m2) <= expected_m2 * AREA_REL_TOL:
			print("  ok    : outline area %.0f m^2 matches the _BF_OUTLINE shape (%.0f m^2) — mapping is rigid" % [area_m2, expected_m2])
		else:
			fails += 1
			print("  FAIL  : outline area %.0f m^2 vs shape %.0f m^2 — projection distorts the building" % [area_m2, expected_m2])

	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	print("=========================================")
	_finish(world, 0 if fails == 0 else 1)

func _finish(world: Node, code: int) -> void:
	world.queue_free()
	await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)

static func _poly_centroid(poly: PackedVector2Array) -> Vector2:
	var a := 0.0
	var c := Vector2.ZERO
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		var w := p.x * q.y - q.x * p.y
		a += w
		c += (p + q) * w
	if absf(a) < 0.001:
		return Vector2.ZERO
	return c / (3.0 * a)

static func _shoelace(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5

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
