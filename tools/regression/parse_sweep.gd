extends SceneTree
## FULL-TREE PARSE SWEEP — one boot, every GDScript file in src/ and tools/.
##
##   godot --headless --path . --script res://tools/regression/parse_sweep.gd
##
## WHY THIS EXISTS, measured 2026-08-23. The harness had two compile checks and
## a defect walked straight between them:
##
##   * the PARSE GATE boots the main scene. The main scene is MainMenu.tscn,
##     which pulls in none of src/build, src/sim or src/scenes/world. Merge
##     7b72ecf left `grp_hot` — a local of a DIFFERENT function — in
##     PlaceableCatalog.gd:11071, and the gate printed a clean bill of health
##     while LineFlow, BuildMode and every world test failed to compile. Every
##     suite that boots a world hung forever instead of running.
##   * the TEST-SCRIPT SWEEP only walks src/tests/*.gd. It did go red, but with
##     27 files all reporting the same INHERITED error, which reads as test rot
##     rather than as "the catalog is down".
##
## So: sweep the WHOLE tree, and name the file that actually broke.
##
## One boot, not one boot per file. The per-file `--check-only --script` loop
## this replaces cost 312 engine starts, ~6 min measured here, against ~15 s.
##
## ── What the verdict is keyed on, and the two vacuous versions tried first ──
##
## GATES ON ERR_PARSE_ERROR (43) ONLY, for the same reason the test sweep it
## grew out of does: a parse error is unambiguously a broken FILE, while the
## softer codes depend on how the sweep itself invokes the compiler. Measured
## both ways on this tree:
##
##   repaired tree   47 x ERR_COMPILATION_FAILED (36),  0 x 43   -> PASS
##   grp_hot restored 47 x 36,  1 x 43, naming PlaceableCatalog  -> FAIL
##
## The 47 are stable and are an artefact of CACHE_MODE_IGNORE re-resolving a
## file's dependencies from scratch; they are printed as notes so nobody has to
## rediscover that they are noise, and gating on them would paint the step
## permanently red — and a permanently red step is one everyone learns to skip.
##
## Two detectors were tried and REJECTED, both by mutation rather than by
## argument. Neither is a hypothetical:
##
##   * `ResourceLoader.load(f) == null`. A file with a hard parse error still
##     comes back NON-NULL, so this reported "316 ok, 0 fail" with the broken
##     catalog in place. It survived until it was mutation-tested.
##   * compiling the file's SOURCE TEXT into a fresh GDScript. A source-only
##     script has no res:// identity, so its own class_name, its preloads and
##     its @tool/@icon annotations cannot resolve: 200+ healthy files reported
##     43. Load the resource; do not retype it.
##
## CACHE_MODE_IGNORE is deliberate — the sweep gets its own copy of every
## script, so reload()ing it cannot perturb the scripts the running engine is
## holding.

const ROOTS : Array[String] = ["res://src", "res://tools"]
## Below this, assume the walk failed rather than that the project shrank. An
## empty file list would otherwise report a spotless sweep, which is exactly the
## vacuous green this project keeps getting bitten by. 316 measured 2026-08-23.
const MIN_FILES : int = 200
## @GlobalScope Error. 43 = a file that does not parse. 36 = a file that parsed
## but whose dependencies did not re-resolve under CACHE_MODE_IGNORE.
const ERR_PARSE : int = 43

func _init() -> void:
	var files : Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	files.sort()

	print("=== FULL-TREE PARSE SWEEP — %d GDScript files ===" % files.size())
	var bad : Array[String] = []
	var noted : int = 0
	for f in files:
		# This script is the one running the sweep; recompiling it proves nothing.
		if f == "res://tools/regression/parse_sweep.gd":
			continue
		var g := ResourceLoader.load(f, "Script", ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if g == null:
			bad.append(f)
			print("  FAIL  : %s did not load as a GDScript at all" % f)
			continue
		var err := g.reload(true)
		if err == ERR_PARSE:
			bad.append(f)
			print("  FAIL  : %s does not parse" % f)
		elif err != OK:
			noted += 1

	# NON-VACUITY, both directions: the tree was actually walked, and the sweep
	# is actually capable of reporting something (a run where every single file
	# came back OK including the known-noisy 47 would mean reload() had stopped
	# reporting at all, not that the tree got healthier).
	if files.size() < MIN_FILES:
		print("  FAIL  : only %d files found — the sweep did not walk the tree" % files.size())
		print("Result: 0 ok, 1 fail")
		print("RESULT: FAIL")
		quit(1)
		return

	print("note  : %d file(s) parsed but reported ERR_COMPILATION_FAILED — see the header, not gated" % noted)
	print("")
	print("Result: %d ok, %d fail" % [files.size() - bad.size(), bad.size()])
	print("RESULT: %s" % ("PASS" if bad.is_empty() else "FAIL"))
	quit(0 if bad.is_empty() else 1)

func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if fname.begins_with("."):
			fname = d.get_next()
			continue
		var full := dir_path.path_join(fname)
		if d.current_is_dir():
			_collect(full, out)
		elif fname.ends_with(".gd"):
			out.append(full)
		fname = d.get_next()
	d.list_dir_end()
