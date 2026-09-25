extends Node
## MAP OVERLAY — init / open / close / toggle / zoom, headless invariant test.
##
##   godot --headless --path . res://src/tests/test_map_overlay_init.tscn
##
## MUST be invoked with the .tscn passed POSITIONALLY, exactly like
## test_map_frame.gd — NOT via --main-scene. --script cannot load a .tscn at
## all (see test_shredder_machine.gd's header), and --main-scene changes the
## engine's own boot/import order enough that the project's global class
## table (MainWorld -> ... -> LiftBooking) isn't fully built before this
## script parses, which is what actually produced the "Could not find type
## LiftBooking" crash — not anything specific to MapOverlay. Booted the
## test_map_frame.gd way, a statically-typed `MapOverlay.new()` parses fine
## (test_map_frame.gd already does exactly that), so there is no need for
## load(...).new() or untyped reflection here.
##
## Boots a REAL MainWorld.tscn (same as test_map_frame.gd) and wires a
## standalone MapOverlay exactly like HUD._build_map_overlay() does — the
## overlay under test is the real class, not a mock.

const TEST_SLOT := "__mapoverlayinit__"
const BOOT_FRAMES := 80
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT := [
	"user://__mapoverlayinit___save.json",
	"user://__mapoverlayinit___factory.json",
]

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
var _fails := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
	else:
		print("  FAIL  : %s" % msg)
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TEST — MapOverlay init / open / close / toggle / zoom ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(null, 2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var mw := world as MainWorld
	if mw == null or mw.player == null:
		print("FATAL: MainWorld/player missing after boot"); _finish(world, 2); return

	# ── S1 — _ready() init, wired exactly like HUD._build_map_overlay() ──────
	var overlay := MapOverlay.new()
	overlay.main_world = mw
	get_tree().root.add_child(overlay)
	await get_tree().process_frame   # let _ready() run

	_ok(overlay.top_level == true, "S1 top_level == true (projects into viewport space, not HUD's transform)")
	_ok(overlay.z_index == 100, "S1 z_index == 100 (%d)" % overlay.z_index)
	_ok(overlay.mouse_filter == Control.MOUSE_FILTER_IGNORE, "S1 mouse_filter == IGNORE (input routed via HUD._input)")
	_ok(overlay.visible == false, "S1 starts hidden (visible == false)")
	_ok(overlay.is_open() == false, "S1 is_open() == false before any open()")
	_ok(not overlay.is_processing(), "S1 processing OFF before open() (set_process(false) in _ready)")

	# ── S2 — open(): size matches the live viewport, visibility + process flip,
	# yaw cache matches main_world._world_yaw(). ──────────────────────────────
	var vp_size : Vector2 = overlay.get_viewport().get_visible_rect().size
	overlay.open()
	_ok(overlay.visible == true, "S2 open(): visible == true")
	_ok(overlay.is_open() == true, "S2 open(): is_open() == true")
	_ok(overlay.is_processing(), "S2 open(): processing ON (live redraw)")
	_ok(overlay.size == vp_size,
		"S2 open(): size == viewport visible rect (%s vs %s)" % [str(overlay.size), str(vp_size)])
	var want_yaw : float = float(mw.call("_world_yaw"))
	_ok(is_equal_approx(overlay._yaw_cos, cos(want_yaw)) and is_equal_approx(overlay._yaw_sin, sin(want_yaw)),
		"S2 open(): cached yaw matches main_world._world_yaw() (%.4f rad)" % want_yaw)

	# ── S3 — a real viewport resize is picked up the NEXT open() (the
	# documented backstop for window-resize / fullscreen-toggle). ────────────
	var resized := Vector2i(int(vp_size.x) + 200, int(vp_size.y) + 150)
	var win := overlay.get_window()
	var orig_win_size := win.size
	win.size = resized
	await get_tree().process_frame
	overlay.open()
	var vp_size2 : Vector2 = overlay.get_viewport().get_visible_rect().size
	if vp_size2 == vp_size:
		print("  note  : headless window did not actually resize (%s) — S3 checks the backstop LOGIC instead of a real resize" % str(win.size))
		_ok(overlay.size == vp_size2, "S3 open() still matches the (unchanged) viewport size")
	else:
		_ok(overlay.size == vp_size2,
			"S3 open() picked up the NEW viewport size after a resize (%s -> %s)" % [str(vp_size), str(vp_size2)])
	win.size = orig_win_size   # restore before any later frame reads it

	# ── S4 — handle_zoom(): direction + clamping ──────────────────────────────
	overlay.view_radius_m = 90.0
	overlay.handle_zoom(1)
	_ok(is_equal_approx(overlay.view_radius_m, 90.0 * MapOverlay.ZOOM_STEP),
		"S4 handle_zoom(+1) shrinks view_radius_m by ZOOM_STEP (%.3f)" % overlay.view_radius_m)
	overlay.view_radius_m = 90.0
	overlay.handle_zoom(-1)
	_ok(is_equal_approx(overlay.view_radius_m, 90.0 / MapOverlay.ZOOM_STEP),
		"S4 handle_zoom(-1) grows view_radius_m by 1/ZOOM_STEP (%.3f)" % overlay.view_radius_m)
	overlay.view_radius_m = MapOverlay.MIN_RADIUS
	overlay.handle_zoom(1)
	_ok(is_equal_approx(overlay.view_radius_m, MapOverlay.MIN_RADIUS),
		"S4 handle_zoom(+1) clamps at MIN_RADIUS (%.1f)" % overlay.view_radius_m)
	overlay.view_radius_m = MapOverlay.MAX_RADIUS
	overlay.handle_zoom(-1)
	_ok(is_equal_approx(overlay.view_radius_m, MapOverlay.MAX_RADIUS),
		"S4 handle_zoom(-1) clamps at MAX_RADIUS (%.1f)" % overlay.view_radius_m)

	# ── S5 — close() / toggle() ───────────────────────────────────────────────
	overlay.close()
	_ok(overlay.visible == false, "S5 close(): visible == false")
	_ok(not overlay.is_processing(), "S5 close(): processing OFF")
	overlay.toggle()
	_ok(overlay.visible == true, "S5 toggle() from closed: opens")
	overlay.toggle()
	_ok(overlay.visible == false, "S5 toggle() from open: closes")
	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])

	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("=========================================")
	_finish(world, 0 if _fails == 0 else 1)

## user:// is restored BEFORE the world is freed, then again after: the
## headless teardown segfault lands inside world teardown (CLAUDE.md, 15 of 62
## boots) and never reaches code after it.
func _finish(world: Node, code: int) -> void:
	_wlg.restore()
	if world != null:
		world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(code)

