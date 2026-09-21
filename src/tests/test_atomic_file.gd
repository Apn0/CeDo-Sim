extends Node3D
## CRASH-SAFE PERSISTENCE — AtomicFile and the writers that now use it.
##
##   godot --headless --path <proj> res://src/tests/test_atomic_file.tscn
##
## THE BUG THIS GUARDS. Every save path used to open its live file with
## FileAccess.WRITE (truncates to 0 bytes immediately) and only then stream the
## JSON in. A kill / crash / full disk in between left an empty or half-written
## file, and the loaders read that as "no data": BuildMode loaded an EMPTY
## factory and WorldLayout fell back to the demo spawns, after which the 60 s
## autosave overwrote the damaged file with the empty state. One bad write =
## permanent loss of the operator's whole build. AtomicFile writes a .tmp,
## keeps the last good generation as .bak, and reads back through
## primary -> .tmp -> .bak.
##
##   A. ROUNDTRIP     write/read, UTF-8 byte-length check, no .tmp left behind
##   B. GENERATIONS   the second write leaves the FIRST as .bak
##   C. TRUNCATED     the actual bug: a half-written primary recovers from .bak
##   D. BAK NOT POISONED  saving over a corrupt primary must NOT copy the
##                    corruption onto the last good .bak  (the check a naive
##                    "always copy to .bak" implementation fails)
##   E. EMPTY PRIMARY the exact residue FileAccess.WRITE leaves after a kill
##   F. CRASH BEFORE RENAME   primary gone, complete .tmp -> recovered
##   G. ORDER         .tmp (newer) beats .bak (older)
##   H. ALL CORRUPT   returns null cleanly — no crash, no garbage
##   I. VALIDATOR     a payload that fails validation never touches disk
##   J. ROOT TYPE     a valid JSON array where an object is required = corrupt
##   K. UNWRITABLE    a failed write is REPORTED, not swallowed
##   L. QUARANTINE    the corrupt primary is kept (copied) once, not piled up
##   M. exists_any    a lone .bak is NOT a save (it is what a delete leaves); a
##                    crash-left complete .tmp is
##   P. DELETES STAY DELETED  removing only the primary must not let the .bak
##                    resurrect the deleted save / macro / new-world slot
##   N. BUILDMODE     end to end: a truncated per-save layout no longer loads as
##                    an empty factory
##   O. WORLDLAYOUT   end to end: a truncated world_layout no longer reverts the
##                    world to the demo spawns
##
## NON-VACUITY: every recovery check is preceded by a check that the UNDAMAGED
## file yields the data, so an implementation that returns nothing cannot pass.
##
## user:// SAFETY: touches only names starting `__atomicfile_` (its own dir, one
## BuildMode slot, one WorldLayout scratch path via layout_path_override). The
## real world_layout.json and every real save are never opened. Everything it
## creates is removed in _finish().

const Scopes := preload("res://src/build/HmiScopes.gd")

const DIR := "user://__atomicfile_test"
const SLOT := "user://__atomicfile_slot_factory.json"
const WL := "user://__atomicfile_worldlayout.json"

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _ready() -> void:
	print("=== ATOMIC FILE — crash-safe persistence ===")
	_clean()
	DirAccess.make_dir_recursive_absolute(DIR)
	_check_helper()
	await _check_buildmode()
	_check_worldlayout()
	_finish()


# ─── helpers ─────────────────────────────────────────────────────────────────
func _p(name: String) -> String:
	return "%s/%s" % [DIR, name]


func _raw_write(path: String, text: String) -> void:
	# Deliberately NOT AtomicFile — this is how the test simulates damage.
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)
		f.close()


func _raw_read(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


## Cut a file to `keep` of its bytes: what a kill mid-store_string leaves behind.
func _truncate(path: String, keep: float) -> void:
	var t := _raw_read(path)
	_raw_write(path, t.substr(0, int(float(t.length()) * keep)))


func _rm(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


func _corrupt_siblings(path: String) -> Array[String]:
	var out : Array[String] = []
	var dir_path := path.get_base_dir()
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	var prefix := path.get_file() + AtomicFile.CORRUPT_TAG
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not d.current_is_dir() and n.begins_with(prefix):
			out.append("%s/%s" % [dir_path, n])
		n = d.get_next()
	d.list_dir_end()
	return out


# =============================================================================
# A–M. the helper itself
# =============================================================================
func _check_helper() -> void:
	# UTF-8 on purpose: the byte-length verification must compare BYTES. Dutch
	# operator vocabulary is exactly what this project stores.
	var gen1 := {"gen": 1, "name": "sorteerlijn — trilzeef ë", "pos": [1.5, 0.0, -2.25]}
	var gen2 := {"gen": 2, "name": "maalmolen — flotatietank", "pos": [3.0, 0.0, 4.0]}
	var gen3 := {"gen": 3, "name": "waslijn", "pos": [9.0, 0.0, 9.0]}
	var path := _p("a.json")

	print("\n-- A. roundtrip --")
	_ok(AtomicFile.write_json(path, gen1) == OK, "write_json returns OK")
	var r1 = AtomicFile.read_json(path, TYPE_DICTIONARY)
	_ok(r1 is Dictionary and int((r1 as Dictionary).get("gen", 0)) == 1, "read_json returns what was written")
	_ok(AtomicFile.last_source == "primary", "served from the primary (got '%s')" % AtomicFile.last_source)
	_ok(String((r1 as Dictionary).get("name", "")) == "sorteerlijn — trilzeef ë", "UTF-8 text survives the roundtrip")
	_ok(not FileAccess.file_exists(path + AtomicFile.TMP_SUFFIX), "no .tmp left behind after a successful write")
	_ok(not FileAccess.file_exists(path + AtomicFile.BAK_SUFFIX), "the very first write has nothing to back up")
	var on_disk := FileAccess.open(path, FileAccess.READ)
	var disk_len := on_disk.get_length() if on_disk != null else -1
	if on_disk != null: on_disk.close()
	_ok(disk_len == JSON.stringify(gen1, "\t").to_utf8_buffer().size(),
		"file is exactly the UTF-8 byte length of the JSON (%d bytes)" % disk_len)

	print("\n-- B. generations --")
	_ok(AtomicFile.write_json(path, gen2) == OK, "second write OK")
	var bak = JSON.parse_string(_raw_read(path + AtomicFile.BAK_SUFFIX))
	_ok(bak is Dictionary and int((bak as Dictionary).get("gen", 0)) == 1, ".bak holds generation 1")
	var cur = JSON.parse_string(_raw_read(path))
	_ok(cur is Dictionary and int((cur as Dictionary).get("gen", 0)) == 2, "primary holds generation 2")

	print("\n-- C. truncated primary (the actual bug) --")
	_truncate(path, 0.4)
	_ok(JSON.parse_string(_raw_read(path)) == null, "precondition: the truncated primary really is unparseable")
	var r3 = AtomicFile.read_json(path, TYPE_DICTIONARY)
	_ok(r3 is Dictionary and int((r3 as Dictionary).get("gen", 0)) == 1,
		"recovered generation 1 from .bak instead of returning nothing")
	_ok(AtomicFile.last_source == "bak", "reported source is 'bak' (got '%s')" % AtomicFile.last_source)

	print("\n-- L. quarantine keeps the evidence, once --")
	var q1 := _corrupt_siblings(path)
	_ok(q1.size() == 1, "one .corrupt-<hash> copy of the damaged primary exists (found %d)" % q1.size())
	AtomicFile.read_json(path, TYPE_DICTIONARY)
	AtomicFile.read_json(path, TYPE_DICTIONARY)
	_ok(_corrupt_siblings(path).size() == 1, "re-reading the same damage does not pile up copies")

	print("\n-- D. a corrupt primary must not poison the last good .bak --")
	_ok(AtomicFile.write_json(path, gen3) == OK, "save over the still-corrupt primary succeeds")
	var bak_after = JSON.parse_string(_raw_read(path + AtomicFile.BAK_SUFFIX))
	_ok(bak_after is Dictionary and int((bak_after as Dictionary).get("gen", 0)) == 1,
		".bak is STILL generation 1 (not overwritten with the corrupt primary)")
	var prim_after = JSON.parse_string(_raw_read(path))
	_ok(prim_after is Dictionary and int((prim_after as Dictionary).get("gen", 0)) == 3, "primary now holds generation 3")

	print("\n-- E. empty primary (exact residue of FileAccess.WRITE + kill) --")
	_raw_write(path, "")
	var r5 = AtomicFile.read_json(path, TYPE_DICTIONARY)
	_ok(r5 is Dictionary and int((r5 as Dictionary).get("gen", 0)) == 1, "0-byte primary recovers from .bak")

	print("\n-- F. crash between remove and rename: primary gone, complete .tmp --")
	var pf := _p("f.json")
	_raw_write(pf + AtomicFile.TMP_SUFFIX, JSON.stringify(gen2))
	_ok(not FileAccess.file_exists(pf), "precondition: no primary")
	var r6 = AtomicFile.read_json(pf, TYPE_DICTIONARY)
	_ok(r6 is Dictionary and int((r6 as Dictionary).get("gen", 0)) == 2, "complete .tmp is recovered")
	_ok(AtomicFile.last_source == "tmp", "reported source is 'tmp' (got '%s')" % AtomicFile.last_source)

	print("\n-- G. .tmp (newer) beats .bak (older) --")
	var pg := _p("g.json")
	_raw_write(pg, "{ this is not json")
	_raw_write(pg + AtomicFile.TMP_SUFFIX, JSON.stringify(gen3))
	_raw_write(pg + AtomicFile.BAK_SUFFIX, JSON.stringify(gen1))
	var r7 = AtomicFile.read_json(pg, TYPE_DICTIONARY)
	_ok(r7 is Dictionary and int((r7 as Dictionary).get("gen", 0)) == 3, "picked the .tmp generation, not the .bak")

	print("\n-- H. everything corrupt --")
	var ph := _p("h.json")
	_raw_write(ph, "{{{")
	_raw_write(ph + AtomicFile.TMP_SUFFIX, "")
	_raw_write(ph + AtomicFile.BAK_SUFFIX, "[1,2")
	var r8 = AtomicFile.read_json(ph, TYPE_DICTIONARY)
	_ok(r8 == null, "returns null (no crash, no garbage)")
	_ok(AtomicFile.last_source == "", "last_source is empty")

	print("\n-- I. validator rejection never touches disk --")
	var pi := _p("i.json")
	AtomicFile.write_json(pi, gen1)
	var before_i := _raw_read(pi)
	var never := func(_t: String) -> bool: return false
	_ok(AtomicFile.write_text(pi, "{\"gen\": 99}", never) == ERR_INVALID_DATA, "rejected write returns ERR_INVALID_DATA")
	_ok(_raw_read(pi) == before_i, "primary is byte-identical after the rejected write")
	_ok(not FileAccess.file_exists(pi + AtomicFile.TMP_SUFFIX), "no .tmp left behind by the rejected write")

	print("\n-- J. wrong root type counts as corrupt --")
	var pj := _p("j.json")
	AtomicFile.write_json(pj, gen1)
	AtomicFile.write_json(pj, [1, 2, 3])    # valid JSON, but an Array
	var r9 = AtomicFile.read_json(pj, TYPE_DICTIONARY)
	_ok(r9 is Dictionary and int((r9 as Dictionary).get("gen", 0)) == 1,
		"an Array primary is rejected for a Dictionary reader; .bak (a Dictionary) is served")
	var r9b = AtomicFile.read_json(pj, TYPE_ARRAY)
	_ok(r9b is Array and (r9b as Array).size() == 3, "the same file is served as-is to an Array reader")

	print("\n-- K. an unwritable destination is reported, not swallowed --")
	var err_k := AtomicFile.write_json("%s/no_such_dir/k.json" % DIR, gen1)
	_ok(err_k != OK, "write into a missing directory returns an error (%d)" % err_k)

	print("\n-- M. exists_any: a lone .bak is NOT a save, a crash-left .tmp is --")
	var pm := _p("m.json")
	_ok(not AtomicFile.exists_any(pm), "false when nothing exists")
	_raw_write(pm + AtomicFile.BAK_SUFFIX, JSON.stringify(gen1))
	_ok(not AtomicFile.exists_any(pm), "false when only the .bak exists (that is what a delete leaves)")
	_raw_write(pm + AtomicFile.TMP_SUFFIX, JSON.stringify(gen2))
	_ok(AtomicFile.exists_any(pm), "true when a complete .tmp exists (crash mid-swap)")

	print("\n-- P. deletes stay deleted --")
	# The game deletes a save / new-worlds a slot / resets a macro by removing the
	# PRIMARY file. A .bak left behind by that must never bring it back.
	var pp := _p("p.json")
	AtomicFile.write_json(pp, gen1)
	AtomicFile.write_json(pp, gen2)                       # primary = gen2, .bak = gen1
	_ok(FileAccess.file_exists(pp + AtomicFile.BAK_SUFFIX), "precondition: a .bak generation exists")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pp))   # what the old delete code did
	_ok(not AtomicFile.exists_any(pp), "after a primary-only delete the slot reads as EMPTY (not 'recoverable')")
	_ok(AtomicFile.read_json(pp, TYPE_DICTIONARY) == null, "the old generation is NOT resurrected from the .bak")
	_ok(AtomicFile.last_source == "", "nothing was served")
	_ok(AtomicFile.delete(pp) == OK, "AtomicFile.delete cleans up the leftovers")
	_ok(not FileAccess.file_exists(pp + AtomicFile.BAK_SUFFIX) and not FileAccess.file_exists(pp + AtomicFile.TMP_SUFFIX),
		"delete() removed the whole .bak/.tmp family")
	# ...and a NEW save under the same name starts clean: its first write has
	# nothing to back up, so a later damaged primary has no stale .bak to fall to.
	AtomicFile.write_json(pp, gen3)
	_truncate(pp, 0.3)
	_ok(AtomicFile.read_json(pp, TYPE_DICTIONARY) == null,
		"a damaged fresh save does NOT fall back to the previous, deleted world")


# =============================================================================
# N. BuildMode end to end
# =============================================================================
func _check_buildmode() -> void:
	print("\n-- N. BuildMode: truncated per-save layout keeps the factory --")
	var ids : Array = Scopes.ORDERED_IDS
	var entries : Array = [{"layout_version": BuildMode.LAYOUT_VERSION}]
	entries.append({"id": ids[0], "x": 4.0, "y": 0.0, "z": 4.0, "rot_y": 0.0, "h": 0.0})
	entries.append({"id": ids[1], "x": 8.0, "y": 0.0, "z": 8.0, "rot_y": 0.0, "h": 0.0})
	_raw_write(SLOT, JSON.stringify(entries))

	var bm := _make_bm()
	add_child(bm)
	await get_tree().process_frame
	var n0 := _placed_under(bm)
	_ok(n0 == 2, "precondition: the undamaged slot loads 2 placed objects (found %d)" % n0)
	bm.call("_save_layout")           # -> .bak = the seed file, primary = the re-save
	_ok(FileAccess.file_exists(SLOT + AtomicFile.BAK_SUFFIX), "_save_layout kept the previous generation as .bak")
	bm.queue_free()
	await get_tree().process_frame

	_truncate(SLOT, 0.45)             # the kill mid-write
	_ok(JSON.parse_string(_raw_read(SLOT)) == null, "precondition: the slot file is now unparseable")
	var bm2 := _make_bm()
	add_child(bm2)
	await get_tree().process_frame
	var n1 := _placed_under(bm2)
	_ok(n1 == 2, "after truncation the factory is RECOVERED — 2 objects, not an empty world (found %d)" % n1)
	bm2.queue_free()
	await get_tree().process_frame


func _make_bm() -> Node:
	var bm := BuildMode.new()
	bm.name = "BuildModeUnderTest"
	bm.layout_path = SLOT
	bm.allow_legacy_fallback = false     # never fall back to the legacy world file
	bm.load_shared_structure = false     # never read or write world_layout.json
	return bm


func _placed_under(bm: Node) -> int:
	var n := 0
	for o in get_tree().get_nodes_in_group("placed_object"):
		if bm.is_ancestor_of(o):
			n += 1
	return n


# =============================================================================
# O. WorldLayout end to end
# =============================================================================
func _check_worldlayout() -> void:
	print("\n-- O. WorldLayout: truncated world_layout.json keeps the world --")
	WorldLayout.layout_path_override = WL
	# Guard the guard: if the override is ignored, the next save() would write the
	# operator's REAL world file. Refuse to continue rather than find out.
	if WorldLayout.get_layout_path() != WL:
		_ok(false, "layout_path_override is honoured — REFUSING to touch the real world file")
		WorldLayout.layout_path_override = ""
		return

	WorldLayout.player_spawn = Vector3(12.5, 0.0, -34.25)
	WorldLayout.factory_center = Vector3(100.0, 0.0, 200.0)
	WorldLayout.save()                                   # generation 1
	WorldLayout.player_spawn = Vector3(99.0, 0.0, 99.0)
	WorldLayout.save()                                   # generation 2 (.bak = generation 1)
	_ok(FileAccess.file_exists(WL + AtomicFile.BAK_SUFFIX), "save() kept the previous generation as .bak")

	WorldLayout.player_spawn = Vector3.ZERO
	WorldLayout.factory_center = Vector3.ZERO
	WorldLayout.call("_load")
	_ok(WorldLayout.player_spawn.is_equal_approx(Vector3(99.0, 0.0, 99.0)),
		"undamaged file loads generation 2 (spawn %s)" % str(WorldLayout.player_spawn))

	_truncate(WL, 0.4)
	_ok(JSON.parse_string(_raw_read(WL)) == null, "precondition: world file is now unparseable")
	WorldLayout.player_spawn = Vector3.ZERO
	WorldLayout.factory_center = Vector3.ZERO
	WorldLayout.call("_load")
	_ok(WorldLayout.player_spawn.is_equal_approx(Vector3(12.5, 0.0, -34.25)),
		"after truncation the world is RECOVERED from .bak (spawn %s)" % str(WorldLayout.player_spawn))
	_ok(WorldLayout.is_configured(), "the recovered world counts as configured (no demo-spawn fallback)")
	WorldLayout.layout_path_override = ""


# =============================================================================
func _clean() -> void:
	var d := DirAccess.open(DIR)
	if d != null:
		d.list_dir_begin()
		var n := d.get_next()
		while n != "":
			if not d.current_is_dir():
				DirAccess.remove_absolute("%s/%s" % [DIR, n])
			n = d.get_next()
		d.list_dir_end()
		DirAccess.remove_absolute(DIR)
	for base in [SLOT, WL]:
		for suffix in ["", AtomicFile.TMP_SUFFIX, AtomicFile.BAK_SUFFIX]:
			_rm(base + suffix)
		for c in _corrupt_siblings(base):
			_rm(c)


func _finish() -> void:
	_clean()
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
