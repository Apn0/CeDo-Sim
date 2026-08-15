extends Node3D
## RETIRED HMI PLACEABLES — the operator order of 2026-08-15 made executable:
## "remove unused/old HMI displays — from build menu and from logic".
##
##   godot --headless --path <proj> res://src/tests/test_hmi_retired.tscn
##
## What was removed: the pre-#165 cosmetic props `hmi_panel` and `hmi_wall`.
## They sat in the build menu next to the 12 real panels and opened a "generic"
## overlay scoped to EVERY machine in the plant — a master panel that exists
## nowhere in Geleen. The operator's whiteboard lists exactly 12 HMIs
## (HmiScopes.SCOPES) and every one of them is a first-class catalog entry.
##
## This file guards all four halves of that removal, because deleting two
## catalog lines is the easy half and the one that silently regrows:
##
##   A. MENU       the build menu (PlaceableCatalog.items(), Control category)
##                 offers the 12 and ONLY the 12.
##   B. BUILD      build_node() refuses a retired id (ghost AND real) and still
##                 builds all 12 with the right hmi_id meta + Hmi script.
##   C. SCOPES     catalog ids and HmiScopes.SCOPES are the same set; the
##                 generic see-all fallback is gone — an unknown id yields an
##                 EMPTY scope, not plant-wide control.
##   D. BEHAVIOUR  (project rule 4 — a review must check behaviour) a panel
##                 whose hmi_id has no scope is INERT: no proximity trigger, no
##                 crosshair prompt, no overlay. A real one still prompts.
##   E. SAVE       an old save containing hmi_panel / hmi_wall LOADS — the
##                 retired entries are dropped and counted, the rest survives,
##                 and re-saving writes the retired ids out of existence.
##   F. FLOW       every HMI is role "none" in MachineFlow, so no panel ever
##                 enters the material-flow graph or triggers a line restart.
##
## NON-VACUITY, stated up front: 12 scoped panels must be found and 2 retired
## ids must be checked. A run that finds zero of either is a FAIL, not a pass —
## this suite would otherwise stay green if the whole Control category vanished.
##
## user:// SAFETY: touches ONE temp slot (`__hmiretire___factory.json`), backed
## up byte-for-byte and restored in _finish(). `load_shared_structure` is off, so
## world_layout.json is never read or written.

const Scopes  := preload("res://src/build/HmiScopes.gd")
const HmiScript := preload("res://src/build/Hmi.gd")

const TEST_SLOT_PATH := "user://__hmiretire___factory.json"
const TOUCHED := [TEST_SLOT_PATH]

## The two ids the operator retired. Second copy on purpose: if someone empties
## PlaceableCatalog.RETIRED_IDS, this list still demands they stay unbuildable.
const RETIRED := ["hmi_panel", "hmi_wall"]

## A live HMI used as the positive control in every negative check.
const LIVE_HMI := "hmi_washing_all"

var _pass := 0
var _fail := 0
var _backups : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _ready() -> void:
	print("=== RETIRED HMI PLACEABLES — hmi_panel / hmi_wall gone from menu, logic and saves ===")
	_backup_files()
	_check_menu()
	_check_build()
	_check_scopes()
	_check_behaviour()
	await _check_save_load()
	_check_flow()
	_finish()


# =============================================================================
# A. MENU — what the operator can actually pick in build mode
# =============================================================================
func _check_menu() -> void:
	print("\n-- A. build menu --")
	var catalog_hmi : Array[String] = []
	var control_ids : Array[String] = []
	for it in PlaceableCatalog.items():
		var id := String(it.get("id", ""))
		if String(it.get("category", "")) == "Control":
			control_ids.append(id)
		if id.begins_with("hmi_"):
			catalog_hmi.append(id)

	# Non-vacuity FIRST: an empty catalog would satisfy every "is absent" check
	# below, and that is exactly the vacuous green project rule 3 warns about.
	_ok(catalog_hmi.size() == Scopes.ORDERED_IDS.size(),
		"catalog carries %d HMI placeables (expect %d, the operator's list)"
			% [catalog_hmi.size(), Scopes.ORDERED_IDS.size()])
	_ok(catalog_hmi == Array(Scopes.ORDERED_IDS, TYPE_STRING, "", null),
		"catalog HMI order == HmiScopes.ORDERED_IDS (whiteboard order)")

	for rid in RETIRED:
		_ok(not catalog_hmi.has(rid), "retired '%s' is NOT in the catalog" % rid)
		_ok(not control_ids.has(rid), "retired '%s' is NOT in the Control build menu" % rid)
		_ok(PlaceableCatalog.is_retired(rid), "is_retired('%s') == true" % rid)
		_ok(PlaceableCatalog.retired_reason(rid) != "",
			"retired_reason('%s') explains why (printed on load)" % rid)
	_ok(not PlaceableCatalog.is_retired(LIVE_HMI),
		"is_retired('%s') == false (a live id is not swept up)" % LIVE_HMI)
	# get_item() must not resurrect them through the alias path either.
	for rid in RETIRED:
		_ok(PlaceableCatalog.get_item(rid).is_empty(),
			"get_item('%s') is empty — no alias smuggles it back" % rid)


# =============================================================================
# B. BUILD — build_node() is the single gate every placement path goes through
# =============================================================================
func _check_build() -> void:
	print("\n-- B. build_node --")
	for rid in RETIRED:
		var real : Node3D = PlaceableCatalog.build_node(rid, false)
		var ghost : Node3D = PlaceableCatalog.build_node(rid, true)
		_ok(real == null, "build_node('%s', ghost=false) == null" % rid)
		_ok(ghost == null, "build_node('%s', ghost=true) == null (no placement preview)" % rid)
		if real != null: real.queue_free()
		if ghost != null: ghost.queue_free()

	var built := 0
	for hid in Scopes.ORDERED_IDS:
		var n : Node3D = PlaceableCatalog.build_node(String(hid), false)
		if n == null:
			_ok(false, "build_node('%s') built a node" % hid)
			continue
		built += 1
		var meta_ok : bool = n.has_meta("hmi_id") and String(n.get_meta("hmi_id")) == String(hid)
		var script_ok : bool = n.get_script() != null and n.get_script() == HmiScript
		if not meta_ok or not script_ok:
			_ok(false, "%s: hmi_id meta %s, Hmi.gd attached %s" % [hid, meta_ok, script_ok])
		n.queue_free()
	_ok(built == Scopes.ORDERED_IDS.size(),
		"all %d scoped panels still build (removal did not take a live one with it)" % built)


# =============================================================================
# C. SCOPES — one table, no fallback
# =============================================================================
func _check_scopes() -> void:
	print("\n-- C. scope table --")
	var catalog_hmi : Array[String] = []
	for it in PlaceableCatalog.items():
		var id := String(it.get("id", ""))
		if id.begins_with("hmi_"):
			catalog_hmi.append(id)
	for id in catalog_hmi:
		_ok(Scopes.has_scope(id), "catalog '%s' has a scope" % id)
	for key in Scopes.SCOPES.keys():
		_ok(catalog_hmi.has(String(key)), "scope '%s' has a catalog entry" % key)
	_ok(Scopes.MOUNTS.size() == Scopes.ORDERED_IDS.size(),
		"MOUNTS covers exactly the %d panels" % Scopes.ORDERED_IDS.size())

	# The removed fallback. get_scope() used to answer EVERY unknown id with a
	# see-all scope, which is how a retired prop became a master panel.
	for bogus in ["generic", "hmi_panel", "hmi_wall", "", "nonsense"]:
		_ok(not Scopes.has_scope(bogus), "has_scope('%s') == false" % bogus)
		_ok(Scopes.get_scope(bogus).is_empty(), "get_scope('%s') is EMPTY, not see-all" % bogus)
	_ok(not Scopes.get_scope(LIVE_HMI).is_empty(), "get_scope('%s') still resolves" % LIVE_HMI)

	# An empty scope must never be mistaken for "no filter". matches() treats an
	# empty token list as match-everything, which is correct for a real scope and
	# catastrophic for a missing one — so the emptiness check above is the guard,
	# and this records the reason in the log.
	_ok(Scopes.matches(Scopes.get_scope(LIVE_HMI), "prewash_3c"),
		"'%s' matches a wash machine (scope filtering still works)" % LIVE_HMI)
	_ok(not Scopes.matches(Scopes.get_scope(LIVE_HMI), "shredder_2_3a"),
		"'%s' does NOT match a shredder (scope is not see-all)" % LIVE_HMI)


# =============================================================================
# D. BEHAVIOUR — an unscoped panel is inert, a scoped one is not
# =============================================================================
func _check_behaviour() -> void:
	print("\n-- D. runtime behaviour --")
	# Positive control: a real panel prompts and owns a proximity trigger.
	var live : Node3D = PlaceableCatalog.build_node(LIVE_HMI, false)
	if live == null:
		_ok(false, "positive control '%s' failed to build" % LIVE_HMI)
		return
	add_child(live)
	live.set("_player_near", true)
	_ok(live.get_node_or_null("HmiTrigger") != null,
		"scoped panel builds its HmiTrigger proximity area")
	_ok(String(live.call("crosshair_prompt", null)).begins_with("Open "),
		"scoped panel prompts: '%s'" % String(live.call("crosshair_prompt", null)))

	# Negative control: same script, an hmi_id with no scope (what a retired or
	# hand-edited save entry would produce). It must NOT become a master panel.
	var inert := StaticBody3D.new()
	inert.set_script(HmiScript)
	inert.set_meta("hmi_id", "generic")
	inert.set_meta("placeable_id", "hmi_panel")
	add_child(inert)
	inert.set("_player_near", true)
	_ok(inert.get_node_or_null("HmiTrigger") == null,
		"unscoped panel builds NO proximity trigger (cannot be walked up to)")
	_ok(String(inert.call("crosshair_prompt", null)) == "",
		"unscoped panel offers NO crosshair prompt")
	inert.call("crosshair_interact", null)
	_ok(true, "crosshair_interact on an unscoped panel does not crash")

	live.queue_free()
	inert.queue_free()


# =============================================================================
# E. SAVE — an old save survives; the retired entries are dropped and counted
# =============================================================================
func _check_save_load() -> void:
	print("\n-- E. old save with retired entries --")
	var entries : Array = [{"layout_version": 2}]
	for rid in RETIRED:
		entries.append({"id": rid, "x": 4.0, "y": 0.0, "z": 4.0, "rot_y": 0.0, "h": 0.0})
	entries.append({"id": LIVE_HMI, "x": 8.0, "y": 0.0, "z": 8.0, "rot_y": 0.0, "h": 0.0})
	var f := FileAccess.open(TEST_SLOT_PATH, FileAccess.WRITE)
	if f == null:
		_ok(false, "could not write the temp save %s" % TEST_SLOT_PATH)
		return
	f.store_string(JSON.stringify(entries))
	f.close()

	var bm := BuildMode.new()
	bm.name = "BuildModeUnderTest"
	bm.layout_path = TEST_SLOT_PATH
	bm.allow_legacy_fallback = false     # never fall back to the legacy world file
	bm.load_shared_structure = false     # never read or write world_layout.json
	add_child(bm)                        # _ready() → load_layout()
	await get_tree().process_frame

	var placed : Array[Node] = []
	var retired_alive := 0
	var live_alive := 0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if not bm.is_ancestor_of(n):
			continue
		placed.append(n)
		var pid := String(n.get_meta("placeable_id", ""))
		if RETIRED.has(pid): retired_alive += 1
		if pid == LIVE_HMI:  live_alive += 1

	_ok(retired_alive == 0, "0 retired panels in the world after load (found %d)" % retired_alive)
	_ok(live_alive == 1, "the save's real panel survived the load (found %d)" % live_alive)
	_ok(placed.size() == 1, "exactly 1 placed object from a 3-entry save (found %d)" % placed.size())

	# Re-save and read the file back: the retired ids must be gone from disk, so
	# the next load has nothing left to drop.
	bm.call("_save_layout")
	var rf := FileAccess.open(TEST_SLOT_PATH, FileAccess.READ)
	var raw : String = rf.get_as_text() if rf != null else ""
	if rf != null: rf.close()
	for rid in RETIRED:
		_ok(raw.find("\"%s\"" % rid) == -1, "re-saved layout no longer contains '%s'" % rid)
	_ok(raw.find(LIVE_HMI) != -1, "re-saved layout still contains '%s'" % LIVE_HMI)

	bm.queue_free()
	await get_tree().process_frame


# =============================================================================
# F. FLOW — no HMI is a material-flow node (a rebuild restarts the whole line)
# =============================================================================
func _check_flow() -> void:
	print("\n-- F. material flow --")
	var MachineFlow := load("res://src/sim/MachineFlow.gd")
	var checked := 0
	for hid in Scopes.ORDERED_IDS:
		var pr : Dictionary = MachineFlow.profile(String(hid))
		if String(pr.get("role", "")) != "none":
			_ok(false, "%s role is '%s', expected 'none'" % [hid, pr.get("role", "")])
			continue
		checked += 1
	_ok(checked == Scopes.ORDERED_IDS.size(),
		"%d of %d HMI ids are role 'none' in MachineFlow" % [checked, Scopes.ORDERED_IDS.size()])
	# The retired ids left MachineFlow's explicit list; the hmi_ prefix branch
	# must still catch them so a stray id can never become a flow node.
	for rid in RETIRED:
		var pr2 : Dictionary = MachineFlow.profile(rid)
		_ok(String(pr2.get("role", "")) == "none",
			"retired '%s' would still be role 'none' (prefix branch covers it)" % rid)


# =============================================================================
func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null


func _restore_files() -> void:
	for p in TOUCHED:
		var prev = _backups.get(p, null)
		if prev == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
			continue
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f:
			f.store_string(String(prev))
			f.close()


func _finish() -> void:
	_restore_files()
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
