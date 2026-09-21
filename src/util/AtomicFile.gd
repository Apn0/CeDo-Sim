extends Object
class_name AtomicFile

## Crash-safe persistence for the files that hold the operator's work
## (world_layout.json, <save>_factory.json, line macros, size overrides, saves).
##
## WHY THIS EXISTS. Every one of those writers used to do
##
##     var f := FileAccess.open(path, FileAccess.WRITE)   # truncates to 0 bytes NOW
##     f.store_string(JSON.stringify(data))               # ...and only then fills it
##
## so a process kill, crash or full disk between the two lines leaves an empty or
## half-written file. The loaders then treated that as "no data" (BuildMode
## -> an empty factory, WorldLayout -> the demo spawns) and the 60 s autosave
## overwrote it with the empty state: one bad write became permanent loss of the
## operator's whole build. The window is real, not theoretical — the headless
## harness segfaults in teardown ~24 % of runs (see CLAUDE.md) and killed runs
## are a documented way to lose in-memory backups.
##
## WRITE  (write_text / write_json)
##   1. optional validator runs on the new text — a payload that would not load
##      back (NaN/Inf, wrong root type) never touches disk;
##   2. the text goes to "<path>.tmp", is flushed and its byte length verified;
##   3. the CURRENT file is copied to "<path>.bak" — but only if it is itself
##      good. A corrupt primary must never overwrite the last good backup;
##   4. "<path>.tmp" is renamed over "<path>".
##
## READ   (read_text / read_json)
##   * primary EXISTS and is good            -> the primary. Nothing else is read.
##   * primary EXISTS but is empty/damaged   -> "<path>.tmp", then "<path>.bak".
##   * primary is MISSING                    -> "<path>.tmp" ONLY.
##   The last rule is deliberate. The game DELETES saves and macros by removing
##   the primary file (new-world wipe, delete-save, macro reset). A .bak left
##   behind by such a delete must never bring the deleted thing back, and a
##   missing primary next to a .bak is exactly what a delete looks like. A crash
##   during the swap looks different: it leaves a complete .tmp. Callers that
##   really delete use AtomicFile.delete(), which removes the whole family.
##   A rejected primary is copied (never moved, never deleted) to
##   "<path>.corrupt-<hash>" once, so the evidence survives the next save.
##
## HONEST LIMITS
##   * Godot exposes no fsync. This defends against a killed/crashed PROCESS and
##     a truncated or failed write; it does not promise anything about an OS
##     crash or power cut with the page cache unflushed.
##   * On Windows DirAccess.rename removes an existing destination first, so the
##     swap in step 4 is not one atomic syscall there. That is exactly why the
##     read side also accepts "<path>.tmp": a crash between the remove and the
##     rename leaves a complete .tmp that read_* recovers.

const TMP_SUFFIX := ".tmp"
const BAK_SUFFIX := ".bak"
const CORRUPT_TAG := ".corrupt-"

## Which candidate the LAST read_* actually used: "primary", "tmp", "bak", or ""
## when nothing usable existed. Diagnostics and tests only — never branch game
## logic on it.
static var last_source : String = ""


## True if there is something to load: the primary, or a complete .tmp that a
## crash mid-swap left behind. A lone .bak does NOT count — that is what a
## deliberate delete leaves (see the READ notes). Use instead of
## FileAccess.file_exists(path) at load sites.
static func exists_any(path: String) -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(path + TMP_SUFFIX)


## Deliberately remove `path` AND its .tmp / .bak, so no older generation can
## come back to life. Quarantined ".corrupt-<hash>" evidence copies are kept.
## Returns OK when nothing is left, else the first error.
static func delete(path: String) -> Error:
	var result : Error = OK
	for p in [path, path + TMP_SUFFIX, path + BAK_SUFFIX]:
		if FileAccess.file_exists(p):
			var err := _rm(p)
			if err != OK and result == OK:
				result = err
	return result


## Crash-safe write. `validator` (optional) is called with the new text and must
## return true for it to be written. Returns OK, or the error that stopped it —
## in every error case the previous primary is left exactly as it was.
## `backup_validator` (optional, defaults to `validator`) judges whether the file
## being REPLACED is a good generation worth keeping as .bak. It is separate
## because "valid" for the old file is not always "valid for the new payload"
## (a valid JSON object is still worth backing up when an array replaces it).
static func write_text(path: String, text: String, validator: Callable = Callable(), backup_validator: Callable = Callable()) -> Error:
	if validator.is_valid() and not bool(validator.call(text)):
		push_error("[AtomicFile] refusing to write %s — new content failed validation (existing file untouched)" % path)
		return ERR_INVALID_DATA

	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		var open_err := FileAccess.get_open_error()
		push_error("[AtomicFile] cannot open %s for writing (error %d)" % [tmp, open_err])
		return open_err if open_err != OK else ERR_FILE_CANT_WRITE
	var stored := f.store_string(text)
	f.flush()
	var write_err := f.get_error()
	f.close()
	if not stored or write_err != OK:
		push_error("[AtomicFile] short write to %s (error %d) — existing file untouched" % [tmp, write_err])
		_rm(tmp)
		return write_err if write_err != OK else ERR_FILE_CANT_WRITE

	# Verify what actually landed. A full disk can fail store_string without
	# raising anything the caller would otherwise see.
	var want := text.to_utf8_buffer().size()
	var chk := FileAccess.open(tmp, FileAccess.READ)
	var got := -1
	if chk != null:
		got = chk.get_length()
		chk.close()
	if got != want:
		push_error("[AtomicFile] %s is %d bytes on disk, expected %d — existing file untouched" % [tmp, got, want])
		_rm(tmp)
		return ERR_FILE_CANT_WRITE

	# Keep the last GOOD generation. Only a primary that would itself pass the
	# validator is allowed to become the backup.
	if FileAccess.file_exists(path):
		if _is_good(_slurp(path), backup_validator if backup_validator.is_valid() else validator):
			_copy(path, path + BAK_SUFFIX)

	var ren := _mv(tmp, path)
	if ren != OK:
		# Windows refuses to rename over an existing file on some paths. The
		# backup above is already safe, so removing the primary here loses
		# nothing, and a crash inside this gap is recovered from .tmp on read.
		_rm(path)
		ren = _mv(tmp, path)
	if ren != OK:
		push_error("[AtomicFile] could not move %s into place (error %d) — the complete new data is preserved as %s" % [path, ren, tmp])
		return ren
	return OK


## Serialise `data` and write it via write_text. The validator re-parses the
## produced text, so anything JSON.stringify emits that would not load back is
## refused instead of replacing a good file.
static func write_json(path: String, data: Variant, indent: String = "\t") -> Error:
	var expect := typeof(data)
	# New text must be JSON of the SAME root type; the file it replaces only has
	# to be valid JSON of any type to earn the .bak slot.
	return write_text(path, JSON.stringify(data, indent), _json_ok.bind(expect), _json_ok.bind(-1))


## Read text with recovery (see the header). Returns "" when nothing usable
## exists; `last_source` says where a non-empty result came from.
static func read_text(path: String, validator: Callable = Callable()) -> String:
	last_source = ""
	var primary_text := ""
	var primary_rejected := false
	var primary_exists := FileAccess.file_exists(path)
	if primary_exists:
		primary_text = _slurp(path)
		if _is_good(primary_text, validator):
			last_source = "primary"
			return primary_text
		primary_rejected = true

	# A MISSING primary may only be recovered from a complete .tmp (crash mid-
	# swap). Its .bak is what a deliberate delete leaves behind — never resurrect.
	var candidates : Array = [[path + TMP_SUFFIX, "tmp"]]
	if primary_exists:
		candidates.append([path + BAK_SUFFIX, "bak"])
	var result := ""
	for cand in candidates:
		if not FileAccess.file_exists(cand[0]):
			continue
		var t := _slurp(cand[0])
		if _is_good(t, validator):
			result = t
			last_source = cand[1]
			break

	if primary_rejected:
		_quarantine(path, primary_text)
		if last_source != "":
			push_warning("[AtomicFile] %s was unreadable (%d bytes) — recovered from %s%s" % [
				path, primary_text.length(), path, TMP_SUFFIX if last_source == "tmp" else BAK_SUFFIX])
		elif primary_text.strip_edges() == "":
			# An empty placeholder (early builds wrote these) with nothing to
			# recover holds no data to lose — a warning, not an error.
			push_warning("[AtomicFile] %s is empty and has no .tmp/.bak to recover from" % path)
		else:
			push_error("[AtomicFile] %s is unreadable (%d bytes) and no valid .tmp/.bak exists — data may be lost" % [path, primary_text.length()])
	elif last_source != "":
		push_warning("[AtomicFile] %s is missing — recovered the complete .tmp a crash left behind" % path)
	return result


## read_text + parse. `expect_type` (a TYPE_* value, e.g. TYPE_DICTIONARY) makes a
## file of the wrong root type count as corrupt; -1 accepts any JSON.
## Returns null when nothing usable exists.
static func read_json(path: String, expect_type: int = -1) -> Variant:
	var text := read_text(path, _json_ok.bind(expect_type))
	if text == "":
		return null
	var j := JSON.new()
	if j.parse(text) != OK:
		return null
	return j.data


# ─── internals ───────────────────────────────────────────────────────────────

static func _slurp(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text()
	f.close()
	return t


static func _is_good(text: String, validator: Callable) -> bool:
	if text.strip_edges() == "":
		return false
	return not validator.is_valid() or bool(validator.call(text))


static func _json_ok(text: String, expect_type: int) -> bool:
	var j := JSON.new()
	if j.parse(text) != OK:
		return false
	return expect_type < 0 or typeof(j.data) == expect_type


## Copy — never move, never delete — a rejected primary aside. Named by content
## hash so re-reading the same corrupt file on every launch does not pile up
## copies.
static func _quarantine(path: String, text: String) -> void:
	if text == "":
		return   # a 0-byte file carries no evidence worth keeping
	var dest := "%s%s%x" % [path, CORRUPT_TAG, text.hash()]
	if FileAccess.file_exists(dest):
		return
	_copy(path, dest)


## The static DirAccess calls take "absolute" paths. MainMenu's own delete code
## globalizes user:// first and only falls back to the raw path "for sandbox", so
## do the same here rather than depend on how each Godot build resolves user://.
static func _abs(path: String) -> String:
	if path.begins_with("user://") or path.begins_with("res://"):
		return ProjectSettings.globalize_path(path)
	return path


static func _rm(path: String) -> Error:
	return DirAccess.remove_absolute(_abs(path))


static func _copy(from: String, to: String) -> Error:
	return DirAccess.copy_absolute(_abs(from), _abs(to))


static func _mv(from: String, to: String) -> Error:
	return DirAccess.rename_absolute(_abs(from), _abs(to))
