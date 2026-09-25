extends Node3D
## PROJECT SWEEP GUARDS (2026-08-23) — three defects found in one sweep of HEAD,
## each of which had already survived at least one review.
##
##   godot --headless --path <proj> res://src/tests/test_project_sweep_guards.tscn
##
## A. DIE-FACE SMOKE — PlaceableCatalog._build_heetafslag_strand_switcher
##    Merge 7b72ecf reverted the smoke pass to a per-strand MeshInstance3D loop
##    that parented into `grp_hot`, a local belonging to a DIFFERENT function
##    further down the file. PlaceableCatalog.gd therefore did not parse, which
##    took LineFlow, BuildMode, MainWorld and every world suite with it: a suite
##    whose script fails to compile boots with NO SCRIPT ATTACHED and idles
##    forever, so the harness hung instead of failing. A parses the RESULT, not
##    the source: the hot strand group must own ONE smoke MultiMesh sized to the
##    strand count, and ZERO loose per-strand MeshInstance3D wisps. Those two
##    facts separate the three candidate implementations — the reverted one does
##    not parse at all, the naive repair (re-parenting the wisp to mmi_hot
##    instead of using the MultiMesh) leaves 20 loose nodes per extruder, and the
##    correct one leaves none.
##
##    WHAT A DELIBERATELY DOES NOT ASSERT, because it CANNOT: the instance
##    transforms themselves. Measured 2026-08-23 on 4.6.3 — under --headless the
##    dummy renderer keeps no CPU-side copy of a MultiMesh, so `buffer` reads
##    back EMPTY and get_instance_transform() returns IDENTITY for every index
##    immediately after a successful set_instance_transform(). A check written
##    against those readings fails on correct code and would have been "fixed"
##    by weakening it. No headless suite in this project can assert MultiMesh
##    CONTENT; assert its shape and its node graph instead.
##
## B. HAND-BUILT WALLS SURVIVE A SAVE — BuildMode._place_current
##    build_wall() is a static helper that never receives the placeable id, and
##    _finalize_placed() only writes height_offset, so a wall placed by the
##    operator carried no `placeable_id` meta. _save_layout() gates on exactly
##    that meta, so the wall was never serialised: draw a partition, save,
##    reload, and the plant is open-plan again. The RELOAD path always stamped
##    the meta itself (BuildMode.gd ~3369), which is why loading a wall worked
##    and saving one never did — and why a files-present review would pass.
##    (FULL_LOGIC_AUDIT_2026-07-08 HIGH #7, still open on 2026-08-23.)
##
## C. CREW TTS IS ACTUALLY CONNECTED — Walkie -> VoiceService
##    C is the one that came back NEGATIVE, and it is in the harness for that
##    reason. FULL_LOGIC_AUDIT_2026-07-08 HIGH #12 calls Walkie._ready()'s
##    connect dead — "VoiceService is autoload #12 (after Walkie #6) -> node
##    doesn't exist yet -> All real TTS crew voice is dead every launch". Godot
##    adds every autoload to /root BEFORE readying them, so the lookup succeeds;
##    probed on a real 4.6.3 boot, /root/VoiceService is present inside
##    Walkie._ready(). C2 was green before any change and stayed green after the
##    prescribed call_deferred, which is what identified the finding as refuted
##    rather than fixed. What C now guards is the LIVE PROPERTY the audit was
##    reaching for and nothing tested: that crew voice is actually wired at all,
##    and wired exactly once.
##
## NON-VACUITY: B and C are useless if the world never booted, so this asserts a
## real BuildMode was found and that WorldLayout.structure_items was EMPTY before
## the wall was placed — otherwise a pre-existing wall would satisfy the check.
##
## MUTATION-PROVEN 2026-08-23 (see docs/AUDIT_project_sweep_2026-08-23.md):
##   restoring the grp_hot loop      -> the whole tscn hangs (no verdict at all)
##   re-parenting the wisp to mmi_hot instead -> A1d red (20 loose wisps)
##   dropping wall.set_meta("placeable_id")    -> B2/B3 red
##   reverting _connect_voice_service to inline -> C2 STAYS GREEN. That is the
##     measurement that refuted audit #12, not a hole in the check: deleting the
##     connect body instead turns C2 red.
##
## user:// SAFETY: same discipline as test_lump_cart_coverage — every touched
## file is byte-backed-up and restored in _finish().

const TEST_SLOT := "__sweepguards__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__sweepguards___save.json", "user://__sweepguards___factory.json",
]

## _build_heetafslag_strand_switcher's own constants. Second copies ON PURPOSE:
## if the builder quietly changes them, A1 measures the drift instead of
## inheriting it.
const STRAND_COUNT : int = 20
const STRAND_H     : float = 0.40
const SMOKE_RISE   : float = STRAND_H * 0.55   # 0.22 m above the strand centre

var _pass := 0
var _fail := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _guarded : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _ready() -> void:
	print("=== PROJECT SWEEP GUARDS — die-face smoke / wall persistence / crew TTS ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return
	_guard_operator_saves()

	_check_die_face_smoke()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	await _check_wall_persistence(world)
	_check_voice_connect()

	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])
	_verify_operator_saves()
	_finish(world)


# =============================================================================
# A — die-face smoke wisps ride their strands
# =============================================================================
func _check_die_face_smoke() -> void:
	print("\n--- A. die-face smoke (PlaceableCatalog strand switcher) ---")
	var unit : Node3D = PlaceableCatalog.build_node("extruder_3a", false)
	_ok(unit != null, "A0 extruder_3a builds at all (the parse error made this null)")
	if unit == null:
		return

	var switcher := _find_meta(unit, "die_face_switcher")
	_ok(switcher != null, "A1a the unit carries a die_face_switcher node")
	if switcher == null:
		unit.free(); return

	var hot := switcher.get_node_or_null("te_heet_strands") as MultiMeshInstance3D
	_ok(hot != null and hot.multimesh != null
			and hot.multimesh.instance_count == STRAND_COUNT,
		"A1b te_heet_strands holds %d strand instances (expected %d)"
			% [(hot.multimesh.instance_count if hot != null and hot.multimesh != null else -1), STRAND_COUNT])
	if hot == null or hot.multimesh == null:
		unit.free(); return

	# The smoke pass is a MultiMesh child of the hot group, NOT 20 loose
	# MeshInstance3D wisps. Both halves matter: the per-strand version is the one
	# that referenced grp_hot, and it also cost 20 nodes per extruder.
	var smoke : MultiMeshInstance3D = null
	var loose := 0
	for c in hot.get_children():
		if c is MultiMeshInstance3D and smoke == null:
			smoke = c
		elif c is MeshInstance3D:
			loose += 1
	_ok(smoke != null and smoke.multimesh != null
			and smoke.multimesh.instance_count == STRAND_COUNT,
		"A1c the hot group owns a smoke MultiMesh with %d instances"
			% (smoke.multimesh.instance_count if smoke != null and smoke.multimesh != null else -1))
	_ok(loose == 0,
		"A1d no per-strand MeshInstance3D wisps were spawned (%d found — 20 means the naive repair)" % loose)
	if smoke == null or smoke.multimesh == null:
		unit.free(); return

	# A2 — the smoke rides the HOT group, not the switcher. It has to be a child
	# of te_heet_strands so show_die_face_state()'s visible flag carries it: smoke
	# hanging off the switcher itself would stay on through TE KOUD and GOED.
	_ok(smoke.get_parent() == hot,
		"A2 the smoke MultiMesh hangs off te_heet_strands, so the state flip hides it too")

	# A3 — the wisp mesh is the spec quad, and it is NOT the same Mesh resource as
	# the strands (sharing one would make the smoke render as cylinders).
	var qm := smoke.multimesh.mesh as QuadMesh
	_ok(qm != null and qm.size.is_equal_approx(Vector2(0.04, 0.06)),
		"A3 the wisp mesh is the 0.04 x 0.06 m quad (got %s)"
			% (str(qm.size) if qm != null else "not a QuadMesh"))
	print("  note  : instance TRANSFORMS are not asserted — the headless dummy")
	print("  note  :   renderer keeps no CPU copy, so buffer reads back empty and")
	print("  note  :   get_instance_transform() returns identity even when set.")

	unit.free()


# =============================================================================
# B — a hand-built wall survives _save_layout()
# =============================================================================
func _check_wall_persistence(world: Node) -> void:
	print("\n--- B. hand-built wall persistence (BuildMode) ---")
	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	_ok(bm != null, "B0 BuildMode found on a real MainWorld boot")
	if bm == null:
		return

	var wall_id := ""
	for it in PlaceableCatalog.items():
		var iid := String((it as Dictionary).get("id", ""))
		if PlaceableCatalog.is_wall(iid):
			wall_id = iid
			break
	_ok(wall_id != "", "B1a the catalog still offers a wall placeable (%s)" % wall_id)
	if wall_id == "":
		return

	# NON-VACUITY: structure_items must be empty first, or a wall shipped with
	# the site would make B2 pass without this placement doing anything.
	var before : int = WorldLayout.structure_items.size()
	_ok(before == 0,
		"B1b WorldLayout.structure_items starts empty (%d entries)" % before)

	# Drive BuildMode's own two-point placement path — not build_wall() directly,
	# because the defect was in the caller, not the builder.
	bm.call("_enter_placing", wall_id)
	bm.call("_spawn_ghost", wall_id)
	var ghost = bm.get("_ghost")
	_ok(ghost != null, "B1c the wall ghost spawned")
	if ghost == null:
		return
	ghost.visible = true
	var a := Vector3(0.0, 0.0, 0.0)
	var b := Vector3(6.0, 0.0, 0.0)
	ghost.global_position = a
	bm.call("_place_current")            # click 1 — stashes the start point
	ghost.global_position = b
	bm.call("_place_current")            # click 2 — builds the wall AND saves
	for _i in range(10):
		await get_tree().process_frame

	var placed : Node = null
	for c in bm.get("_placed_root").get_children():
		if String(c.get_meta("placeable_id", "")).begins_with("wall_"):
			placed = c
			break
	_ok(placed != null,
		"B2 the placed wall carries a placeable_id meta (the key _save_layout gates on)")

	# B3 is the behaviour the operator actually loses: walls are written to the
	# SHARED structure layer, so this is the round-trip the old code silently
	# skipped.
	var found : Dictionary = {}
	for e in WorldLayout.structure_items:
		var d : Dictionary = e
		if String(d.get("id", "")).begins_with("wall_"):
			found = d
			break
	_ok(not found.is_empty(),
		"B3 the wall reached WorldLayout.structure_items (%d entries now)"
			% WorldLayout.structure_items.size())
	if found.is_empty():
		return
	var span_ok : bool = found.has("sx") and found.has("ex") \
		and absf(float(found["sx"]) - a.x) < 0.01 \
		and absf(float(found["ex"]) - b.x) < 0.01
	_ok(span_ok,
		"B4 the serialised wall keeps BOTH endpoints (sx %.2f -> ex %.2f, drew %.2f -> %.2f)"
			% [float(found.get("sx", NAN)), float(found.get("ex", NAN)), a.x, b.x])


# =============================================================================
# C — Walkie is really listening to VoiceService
# =============================================================================
func _check_voice_connect() -> void:
	print("\n--- C. crew TTS hookup (Walkie -> VoiceService) ---")
	var walkie := get_node_or_null("/root/Walkie")
	var vs := get_node_or_null("/root/VoiceService")
	_ok(walkie != null and vs != null,
		"C0 both autoloads exist (Walkie %s, VoiceService %s)"
			% [str(walkie != null), str(vs != null)])
	if walkie == null or vs == null:
		return

	# C1 records the PREMISE, so a future reorder of project.godot that quietly
	# makes the old inline connect work again does not read as this fix working.
	var order : Array = []
	for k in ["Walkie", "VoiceService"]:
		order.append(ProjectSettings.get_setting("autoload/" + k, ""))
	_ok(order[0] != "" and order[1] != "",
		"C1 both autoloads are declared in project.godot (VoiceService is #13, Walkie #6)")

	var cb := Callable(walkie, "_on_voice_done")
	_ok(vs.is_connected("voice_done", cb),
		"C2 VoiceService.voice_done is connected to Walkie._on_voice_done")

	# C3 — idempotence. The deferred hookup must be safe to call twice, or a
	# re-entry would double every synthesised line.
	if walkie.has_method("_connect_voice_service"):
		walkie.call("_connect_voice_service")
		var n : int = 0
		for c in vs.get_signal_connection_list("voice_done"):
			if (c as Dictionary).get("callable") == cb:
				n += 1
		_ok(n == 1, "C3 re-running the hookup does not stack listeners (%d)" % n)
	else:
		_ok(false, "C3 Walkie._connect_voice_service() exists (the deferred hookup)")


# =============================================================================
func _find_meta(root: Node, key: String) -> Node3D:
	if root.has_meta(key):
		return root as Node3D
	for c in root.get_children():
		var hit := _find_meta(c, key)
		if hit != null:
			return hit
	return null


## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish(world: Node = null) -> void:
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	if world != null and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


func _guard_operator_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if not (fn.begins_with("allernieuwste_") and fn.ends_with(".json")):
			continue
		var f := FileAccess.open("user://" + fn, FileAccess.READ)
		if f:
			_guarded["user://" + fn] = f.get_as_text().sha256_text()
			f.close()


func _verify_operator_saves() -> void:
	var changed : Array = []
	for p in _guarded.keys():
		var f := FileAccess.open(String(p), FileAccess.READ)
		if f == null:
			changed.append(p); continue
		if f.get_as_text().sha256_text() != String(_guarded[p]):
			changed.append(p)
		f.close()
	_ok(changed.is_empty(),
		"operator saves untouched (%d changed: %s)" % [changed.size(), str(changed)])
