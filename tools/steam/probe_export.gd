extends SceneTree

## Checks an EXPORTED build of the game from the inside. Runs in the exported
## executable (and, for comparison, in the editor binary on the project):
##
##   APPDATA=<scratch> CeDoSimulator.console.exe --headless \
##       --script <abs path>/tools/steam/probe_export.gd -- --paths=<list file>
##
## Always give it a scratch APPDATA: the exported game's user:// is the SAME
## folder as the editor's (app_userdata/CeDo Simulator), and phase 2 boots a
## real MainWorld, whose autosave writes world_layout.json.
##
## Phase 1: every path in the list file loads (the list is the cache-only
##          assets, whose export gen_export_preset.py exists for); the web HMI
##          pages are readable; machine sounds are found; no API key was taken
##          from a Desktop .env.
## Phase 2: "New game" into MainWorld, then what a player would stand in: the
##          building shell (the fitted building frame), the placed objects, the
##          LineFlow graph.
## Verdict: "Result: N ok, M fail". Read it with the ^SCRIPT ERROR / ^ERROR
## lines of the same log; exit code alone proves nothing.

const DEADLINE_S := 240.0
const WORLD_WAIT_S := 25.0
const HMI_DIR := "res://docs/plant/hmi_screens_2026-07-26/"

var _ok_n := 0
var _fail_n := 0
var _t0 := 0.0
var _phase := 0
var _world : Node = null
var _world_t := 0.0
var _done := false


func _initialize() -> void:
	_t0 = Time.get_ticks_msec() / 1000.0
	print("=== probe_export === editor=%s template=%s" % [OS.has_feature("editor"), OS.has_feature("template")])


func _process(_delta: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not _done and now - _t0 > DEADLINE_S:
		_check(false, "watchdog: probe finished within %d s" % int(DEADLINE_S))
		_finish(2)
		return true
	if _done:
		return true
	match _phase:
		0:
			_phase = 1   # autoloads are in the tree from the first frame on
		1:
			_phase_resources()
			_start_world()
			_phase = 2
		2:
			if now - _world_t >= WORLD_WAIT_S:
				_phase_world()
				_finish(0 if _fail_n == 0 else 1)
	return false


func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok_n += 1
		print("  ok   : " + msg)
	else:
		_fail_n += 1
		print("  FAIL : " + msg)


func _phase_resources() -> void:
	print("[1] resources")
	var list_file := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--paths="):
			list_file = a.trim_prefix("--paths=")
	var paths : PackedStringArray = []
	if list_file != "":
		var txt := FileAccess.get_file_as_string(list_file)
		for l in txt.split("\n", false):
			var p := l.strip_edges()
			if p != "":
				paths.append(p if p.begins_with("res://") else "res://" + p)
	_check(paths.size() > 0, "path list read (%d paths from %s)" % [paths.size(), list_file])
	var bad : PackedStringArray = []
	for p in paths:
		if not ResourceLoader.exists(p) or load(p) == null:
			bad.append(p)
	_check(bad.is_empty(), "%d of %d listed resources load" % [paths.size() - bad.size(), paths.size()])
	for b in bad.slice(0, 15):
		print("         missing: " + b)

	var shell := FileAccess.get_file_as_string(HMI_DIR + "hmi_shell.html")
	_check(shell.length() > 1000, "web HMI shell readable (%d bytes)" % shell.length())
	_check(FileAccess.file_exists(HMI_DIR + "vendor/react@18.3.1.min.js"), "web HMI vendor script present")
	var screens := 0
	var d := DirAccess.open(HMI_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".dc.html"):
				screens += 1
	_check(screens >= 30, "web HMI screen files found (%d .dc.html)" % screens)

	var msb = load("res://src/audio/MachineSoundBank.gd")
	var ids : Array = msb.spec_ids() if msb else []
	_check(ids.size() > 0, "machine sound specs found (%d)" % ids.size())

	var keys := root.get_node_or_null("ApiKeys")
	_check(keys != null, "ApiKeys autoload present")
	if keys and not OS.has_feature("editor"):
		_check(keys.google() == "" and keys.openai() == "",
			"exported build took no API key from a Desktop .env")


func _start_world() -> void:
	print("[2] New game -> MainWorld")
	var bus := root.get_node_or_null("EventBus")
	if bus:
		bus.set_meta("pending_save_name", "steam_probe")
		bus.set_meta("pending_is_new_save", true)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_check(scn != null, "MainWorld.tscn loads")
	if scn:
		_world = scn.instantiate()
		root.add_child(_world)
		current_scene = _world   # as change_scene_to_file leaves it; vehicles add to current_scene
	_world_t = Time.get_ticks_msec() / 1000.0


func _phase_world() -> void:
	if _world == null:
		return
	var wl := root.get_node_or_null("WorldLayout")
	print("  info : WorldLayout.is_configured() = %s" % (wl.is_configured() if wl else "n/a"))
	var ilm := _world.find_child("InteriorLightingManager", true, false)
	var frame : Dictionary = ilm.get_building_frame() if ilm and ilm.has_method("get_building_frame") else {}
	_check(not frame.is_empty(), "building shell present (fitted building frame: %s)" % str(frame.keys()))
	var placed := _world.find_child("PlacedObjects", true, false)
	print("  info : PlacedObjects children = %d" % (placed.get_child_count() if placed else -1))
	var lf := _world.find_child("LineFlow", true, false)
	var n_nodes := -1
	if lf and "_nodes" in lf:
		n_nodes = (lf.get("_nodes") as Array).size()
	print("  info : LineFlow nodes = %d" % n_nodes)
	print("  info : scene tree node count = %d" % _count(root))


func _count(n: Node) -> int:
	var c := 1
	for ch in n.get_children():
		c += _count(ch)
	return c


func _finish(code: int) -> void:
	_done = true
	print("Result: %d ok, %d fail" % [_ok_n, _fail_n])
	quit(code)
