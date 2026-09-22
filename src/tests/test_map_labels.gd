extends Node
## MAP WAYFINDING LABELS (Q5, 2026-09-23) — the site map names machines by their
## catalog display name (Dutch operator vocabulary), names the crew dots, and
## draws every placed HMI panel with its scope label.
##
##   godot --headless --path . res://src/tests/test_map_labels.tscn
##
## Boots a REAL MainWorld.tscn (the operator's world_layout.json is read, never
## written — it is backed up and byte-compared at the end) so the crew labels
## are read off real NPCs; places two real HMI panels through the catalog so
## hmi_markers() has something to find whatever the world holds; then opens a
## MapOverlay wired like HUD does, zooms it to its closest radius (labels are
## only drawn past scale_px 3) and redraws — the log's zero SCRIPT ERROR lines
## are the "the draw path runs" proof, the checks below are the content model.

const TEST_SLOT := "__maplabels__"
const BOOT_FRAMES := 80
const WATCHDOG_S := 240.0
const PROTECT := [
	"user://world_layout.json",
	"user://__maplabels___save.json",
	"user://__maplabels___factory.json",
]

var _backups : Dictionary = {}
var _fails := 0
var _oks := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _backup_files() -> void:
	for p in PROTECT:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				_backups[p] = f.get_buffer(f.get_length())
				f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in PROTECT:
		var had = _backups.get(p, null)
		if had == null:
			if p.find(TEST_SLOT) >= 0:
				AtomicFile.delete(p)
			continue
		var now : PackedByteArray = PackedByteArray()
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				now = f.get_buffer(f.get_length())
				f.close()
		if now != had:
			var w := FileAccess.open(p, FileAccess.WRITE)
			if w != null:
				w.store_buffer(had)
				w.close()
			print("  note  : restored %s (it had changed during the test)" % p)

func _run() -> void:
	print("[TEST] map wayfinding labels")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_backup_files()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	# ── S1: pure label helpers, no world needed ──
	var item : Dictionary = PlaceableCatalog.get_item("vw_trommel")
	_check(not item.is_empty(), "S1 catalog knows vw_trommel (name '%s')" % String(item.get("name", "")))
	var lbl := MapOverlay.machine_label_for("vw_trommel_2")
	_check(lbl != "" and lbl != "vw_trommel" and lbl != "vw_trommel_2",
		"S1 machine label for 'vw_trommel_2' is the catalog name, not the id ('%s')" % lbl)
	_check(lbl.find("(") < 0 and lbl.find("—") < 0, "S1 the label is cut before any '(' or '—' ('%s')" % lbl)
	var cart_lbl := MapOverlay.machine_label_for("lump_cart")
	_check(cart_lbl == "Lumpenwagen", "S1 'lump_cart' → 'Lumpenwagen' (got '%s')" % cart_lbl)
	_check(MapOverlay.machine_label_for("no_such_machine_3") == "no_such_machine",
		"S1 unknown id falls back to the trimmed id ('%s')" % MapOverlay.machine_label_for("no_such_machine_3"))
	var plain := Node3D.new()
	plain.name = "yassine"
	_check(MapOverlay.crew_label_for(plain) == "Yassine", "S1 crew label capitalises a node name ('%s')" % MapOverlay.crew_label_for(plain))
	plain.free()

	# ── boot the real world ──
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(null); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	var mw := world as MainWorld
	if mw == null or mw.player == null:
		print("FATAL: MainWorld/player missing after boot"); _finish(world); return

	# ── S2: crew labels off real NPCs ──
	var npcs : Array = mw.npcs.values()
	_check(npcs.size() >= 5, "S2 the world spawned a crew (%d NPCs)" % npcs.size())
	var unnamed : Array = []
	var seen := {}
	var dup : Array = []
	for n in npcs:
		var cl := MapOverlay.crew_label_for(n as Node)
		if cl.strip_edges() == "":
			unnamed.append((n as Node).name)
		if seen.has(cl):
			dup.append(cl)
		seen[cl] = true
	_check(unnamed.is_empty(), "S2 every crew dot has a name (unnamed: %s)" % str(unnamed))
	_check(dup.is_empty(), "S2 crew names are distinct (dupes: %s)" % str(dup))
	if not npcs.is_empty():
		var n0 := npcs[0] as Node
		var want := String(n0.get("npc_name")).capitalize() if "npc_name" in n0 else String(n0.name).capitalize()
		_check(MapOverlay.crew_label_for(n0) == want and want != "", "S2 first worker's label is its npc_name capitalised ('%s')" % want)

	# ── S3: HMI markers — place two real panels, find both with their scope labels ──
	var hmi_before : int = get_tree().get_nodes_in_group("hmi").size()
	var pa : Node3D = PlaceableCatalog.build_node("hmi_shredder_l1", false)
	var pb : Node3D = PlaceableCatalog.build_node("hmi_washing_all", false)
	_check(pa != null and pb != null, "S3 two real HMI panels built through the catalog")
	if pa == null or pb == null:
		_finish(world); return
	world.add_child(pa)
	world.add_child(pb)
	pa.global_position = mw.player.global_position + Vector3(4.0, 0.0, 0.0)
	pb.global_position = mw.player.global_position + Vector3(0.0, 0.0, 4.0)
	await get_tree().process_frame
	var overlay := MapOverlay.new()
	overlay.main_world = mw
	get_tree().root.add_child(overlay)
	await get_tree().process_frame
	var markers := overlay.hmi_markers()
	_check(markers.size() == hmi_before + 2, "S3 hmi_markers() lists every 'hmi' group node (%d = %d + 2)" % [markers.size(), hmi_before])
	var labels := {}
	for m in markers:
		labels[String((m as Dictionary)["label"])] = (m as Dictionary)["pos"]
	_check(labels.has("Shredder lijn 1"), "S3 the shredder panel is labelled by its scope ('Shredder lijn 1' in %s)" % str(labels.keys()))
	_check(labels.has("Waslijn (alle lijnen)"), "S3 the washing panel is labelled by its scope")
	if labels.has("Shredder lijn 1"):
		_check((labels["Shredder lijn 1"] as Vector3).distance_to(pa.global_position) < 0.001, "S3 marker position is the panel's scene position")
	_check(String(pa.call("scope_label")) == "Shredder lijn 1", "S3 Hmi.scope_label() reads the resolved scope")

	# ── S4: draw path at the closest zoom (labels only draw past scale_px 3) ──
	overlay.open()
	# open() sizes the panel from the viewport, which under the dummy display
	# server is a 64 px window (measured: scale_px 1.05 at the closest radius) —
	# labels only draw past scale_px 3, so give it a real window's worth of pixels.
	overlay.size = Vector2(1152.0, 648.0)
	for _z in 12:
		overlay.handle_zoom(1)
	var vp : Dictionary = overlay.view_params()
	_check(float(vp["scale_px"]) > 5.0, "S4 zoomed in far enough for labels (scale_px %.2f)" % float(vp["scale_px"]))
	overlay.queue_redraw()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(overlay.is_open(), "S4 overlay still open after two redraws with labels, crew names and HMI diamonds (no SCRIPT ERROR above = the draw ran)")
	overlay.close()
	overlay.queue_free()
	_finish(world)

func _finish(world: Node) -> void:
	if world != null and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	_restore_files()
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] map wayfinding labels %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
