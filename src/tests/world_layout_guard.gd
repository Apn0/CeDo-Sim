extends RefCounted
## WORLD LAYOUT LEAK GUARD — keeps a MainWorld suite's world saves out of the
## operator's user://world_layout.json, and proves it every run.
##
## WHY. user://world_layout.json is the world's ground truth and is in git
## nowhere. A booted MainWorld writes it on every placement and on the 60 s
## autosave: SaveCoordinator.save_game -> BuildMode._save_layout ->
## WorldLayout.save(), whenever load_shared_structure is true (it is, on the
## world's own BuildMode). A new-save boot saves once more straight away. The
## suites used to guard the file with an in-memory copy written back in
## _finish(), AFTER queue_free(). A kill, a SUITE_TIMEOUT or the headless
## teardown segfault (CLAUDE.md, 15 of 62 boots) skipped that write-back and left
## the file as the world last saved it. That is how "3A/3B gate (jam-baseline
## fixture)" reached his file on 2026-09-24
## (docs/audit/jam_baseline_layout_leak_2026-09-24.md). Every save also rotated
## AtomicFile's world_layout.json.bak, which the raw write-back never repaired.
##
## WHAT IT DOES
##   arm()          before MainWorld boots: snapshot the slot's own files and the
##                  real layout family, point WorldLayout's writes at
##                  user://<slot>_world_layout.json, refuse if that does not take.
##                  WorldLayout has already loaded the operator's file in its own
##                  _ready, so the world still boots on his real markers; only the
##                  WRITES move.
##   final_checks() two LEAK GUARD checks for the suite's verdict (see there).
##   restore()      put the slot's files back. Call it before the world is freed
##                  AND after. Unchanged bytes are never rewritten.
##   disarm()       remove the scratch layout.
##
## The real world_layout.json is NEVER written by this guard, not even to
## restore it. With the redirect armed a suite cannot change it, so a change was
## made by someone else sharing this app_userdata (the game, another harness)
## or it is a leak that final_checks() reports red. Writing the start-of-run
## bytes over it would revert the first and hide the second. Same rule as
## test_legacy_props_spawner (#281); tools/regression/run.sh's sentinel reports
## the same file between suites and never restores it either.
##
## USE — preload it, never a class_name: a fresh class_name is unknown to a
## standalone headless run until the editor rebuilds its class cache (CLAUDE.md).
##
##   const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
##   var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)   # PROTECT: slot files only
##   # _ready, before MainWorld.tscn is instantiated:
##   if not _wlg.arm(get_tree()): get_tree().quit(2); return
##   # before the verdict and before ANY restore:
##   for c in _wlg.final_checks(world): _check(c[0], c[1])
##   # _finish:
##   _wlg.restore(); world.queue_free(); await get_tree().process_frame
##   _wlg.restore(); _wlg.disarm(); get_tree().quit(code)

const REAL : String = "user://world_layout.json"
## AtomicFile keeps a .bak and, mid-swap, a .tmp beside every file it writes. A
## save rotates .bak even when it writes the same bytes, so all three are watched.
const REAL_FAMILY : Array[String] = [REAL, REAL + ".bak", REAL + ".tmp"]

## This suite's layout file. Every world save lands here while armed.
var scratch : String = ""
## WorldLayout.save() calls seen while armed: boot, placement, autosave and the
## forced save in final_checks(). Printed, so a reader can see what the final
## check covered.
var saves : int = 0

var _slot_files : Array[String] = []
## slot file -> PackedByteArray, or null when it did not exist before the run.
var _backups : Dictionary = {}
## Every .tmp/.bak beside a slot file that existed before the run. Those are an
## earlier run's leftovers and restore() leaves them where they are.
var _siblings_before : Dictionary = {}
## REAL_FAMILY path -> "md5@mtime", or "absent".
var _real_before : Dictionary = {}
## Start-of-run bytes of REAL, kept beside it if it changes (see restore()).
var _real_bytes : Variant = null
var _kept_real : bool = false
var _wl : Node = null
var _slot : String = ""

func _init(slot: String, slot_files: Array = []) -> void:
	_slot = slot
	scratch = "user://%s_world_layout.json" % slot
	for p in slot_files:
		if not REAL_FAMILY.has(String(p)):
			_slot_files.append(String(p))

## Call BEFORE MainWorld.tscn is instantiated. False, after a FATAL line, when
## the redirect does not take: the caller must not boot a world then.
func arm(tree: SceneTree) -> bool:
	_wl = tree.root.get_node_or_null("WorldLayout")
	if _wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		return false
	for p in _slot_files:
		_backups[p] = _read_or_null(p)
		for s in [p + ".tmp", p + ".bak"]:
			if FileAccess.file_exists(s):
				_siblings_before[s] = true
	for p in REAL_FAMILY:
		_real_before[p] = _stamp(p)
	_real_bytes = _read_or_null(REAL)
	AtomicFile.delete(scratch)   # a killed earlier run can leave one behind
	_wl.set("layout_path_override", scratch)
	if String(_wl.call("get_layout_path")) != scratch:
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run "
			+ "(every world save would rewrite the operator's %s)" % REAL)
		_wl.set("layout_path_override", "")
		return false
	_wl.connect("layout_changed", _on_saved)
	print("  info  : world saves redirected to %s; %s is %s before boot"
		% [scratch, REAL, _real_before[REAL]])
	return true

## The two LEAK GUARD checks, as [passed, label] pairs for the suite's own check
## function. Call them before the verdict and BEFORE any restore.
##  1. A world save forced now lands in the scratch file. It is the autosave's
##     own call, BuildMode._save_layout on the world's "BuildMode" child. Without
##     it, an untouched real file cannot tell a redirected save from no save at
##     all (a suite that never places anything and ends before the first
##     autosave). The scratch file is deleted first, so only this save can
##     have written it.
##  2. world_layout.json, .bak and .tmp are exactly as before boot, by md5 AND
##     mtime. md5 alone cannot see a save that wrote the same bytes, and such a
##     save still rotates .bak and opens the file for writing.
func final_checks(world: Node) -> Array:
	var bm : Node = null
	if world != null and is_instance_valid(world):
		bm = world.get_node_or_null("BuildMode")
	var landed := false
	var why := "the world has no BuildMode child"
	if bm != null and bm.has_method("_save_layout"):
		AtomicFile.delete(scratch)
		var before := saves
		bm.call("_save_layout")
		landed = saves > before and FileAccess.file_exists(scratch)
		why = "%d save signalled, scratch %s" % [saves - before,
			"written" if FileAccess.file_exists(scratch) else "NOT written"]
	return [
		[landed, "LEAK GUARD: a forced world save (BuildMode._save_layout, the autosave's own call) went to %s (%s)"
			% [scratch, why]],
		real_layout_check(),
	]

## Check 2 of final_checks() alone, for a suite that boots no world (or whose
## world is gone), as one [passed, label] pair.
func real_layout_check() -> Array:
	if _real_before.is_empty():
		return [false, "LEAK GUARD: arm() never took its snapshot, so the operator's world_layout.json was not watched"]
	var changed := _real_changes()
	return [changed.is_empty(), "LEAK GUARD: the operator's world_layout.json, .bak and .tmp are untouched after %d world save(s) (md5 + mtime as before the run)%s"
		% [saves, "" if changed.is_empty() else " — CHANGED: " + "; ".join(changed)]]

## Put the slot's files back. A file whose bytes are unchanged is not rewritten.
## One that did not exist before is deleted, with the .tmp/.bak this run gave
## it. Safe to call more than once, and a no-op before arm() took its snapshot.
## The real world_layout.json is never written (see the header).
func restore() -> void:
	if _real_before.is_empty():
		return
	for p in _slot_files:
		var data : Variant = _backups.get(p, null)
		if typeof(data) == TYPE_NIL:
			for f in [p, p + ".tmp", p + ".bak"]:
				if FileAccess.file_exists(f) and not _siblings_before.has(f):
					DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		elif not _same_bytes(_read_or_null(p), data):
			AtomicFile.write_text(p, (data as PackedByteArray).get_string_from_utf8())
	_keep_real_if_changed()

## Remove the scratch layout; AtomicFile.delete takes its .tmp/.bak with it. The
## override stays pointed at it: the process quits next, and lifting it would
## only give a late save() a path to the real file.
func disarm() -> void:
	AtomicFile.delete(scratch)

func _on_saved() -> void:
	saves += 1

func _real_changes() -> Array[String]:
	var out : Array[String] = []
	for p in REAL_FAMILY:
		var now := _stamp(p)
		if now != String(_real_before.get(p, "")):
			out.append("%s %s -> %s" % [p.get_file(), _real_before.get(p, "?"), now])
	return out

## A changed real file is left as is. The start-of-run copy is kept beside it,
## once, so neither version is lost.
func _keep_real_if_changed() -> void:
	if _kept_real or _real_before.is_empty() or _same_bytes(_read_or_null(REAL), _real_bytes):
		return
	_kept_real = true
	if typeof(_real_bytes) == TYPE_NIL:
		print("  WARN  : %s appeared during the run — left as is" % REAL)
		return
	var keep := "%s.%s-%d.bak" % [REAL, _slot, int(Time.get_unix_time_from_system())]
	var err := AtomicFile.write_text(keep, (_real_bytes as PackedByteArray).get_string_from_utf8())
	print("  WARN  : %s changed during the run — left as is, NOT restored; the start-of-run copy is %s (%s)"
		% [REAL, keep, error_string(err)])

## "md5@mtime" of a file, or "absent".
static func _stamp(path: String) -> String:
	if not FileAccess.file_exists(path):
		return "absent"
	return "%s@%d" % [FileAccess.get_md5(path), FileAccess.get_modified_time(path)]

static func _read_or_null(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

static func _same_bytes(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_NIL or typeof(b) == TYPE_NIL:
		return typeof(a) == typeof(b)
	return (a as PackedByteArray) == (b as PackedByteArray)
