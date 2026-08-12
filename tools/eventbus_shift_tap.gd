extends Node

# =============================================================================
# LIVE EventBus tap — boots the REAL MainWorld and records a whole shift.
# =============================================================================
# Unlike tools/hidden_machine_tap.gd (which drives one ExtruderModel in
# isolation with synthetic operator inputs), this records what the WHOLE plant
# actually emits: every EventBus signal, in order, with shift time attached.
# Nothing is stubbed — real LineFlow, real CrewManager, real NpcAutonomyBoard,
# real ShiftClock.
#
#   godot --headless --path . res://tools/eventbus_shift_tap.tscn
#
# Env:
#   TAP_OUT        output directory (default user://eventbus_tap)
#   TAP_ACCEL      Engine.time_scale (default 1.0 — see the warning below)
#   TAP_SHIFT_SCALE  ShiftClock.time_scale (default 1.0 = shift seconds ARE
#                  process seconds; the shipped default is 24, which would run
#                  the wall clock 24x faster than the machines)
#   TAP_MAX_WALL_S wall-clock budget before giving up (default 900)
#   TAP_SLOT       save slot name (default __eventbus_tap__)
#   TAP_START_HH / TAP_START_MM  where to seek the clock (default 07:05)
#
# ⚠ TAP_ACCEL > 1 scales physics and process deltas together, but Godot caps
#   physics catch-up at max_physics_steps_per_frame. Above roughly 4x the crew
#   walk in slow motion relative to the process sim, so machine events stay
#   faithful while NPC events get thinned. The tap measures and reports that
#   ratio rather than hiding it — see the drift line at the end of the run.
#
# Writes:
#   events.jsonl   every signal with full args, for forensics
#   stream.log     one symbol per line, ready for hidden-machine --mode lines
#   summary.txt    alphabet, rates, and the physics-drift measurement
# =============================================================================

const BOOT_FRAMES   : int = 120
const SETTLE_FRAMES : int = 120

var _out_dir     : String = "user://eventbus_tap"
var _accel       : float  = 1.0
var _shift_scale : float  = 1.0
var _max_wall_s  : float  = 900.0
var _slot        : String = "__eventbus_tap__"
var _start_hh    : int    = 7
var _start_mm    : int    = 5

var _protect : Array[String] = []
var _backups : Dictionary = {}

var _world  : Node = null
var _clock  : Node = null
var _events : Array = []
var _stream : Array = []

var _t_start_wall  : float = 0.0
var _frames        : int   = 0
var _physics_frames: int   = 0
var _shift_at_start: float = 0.0
var _ended         : bool  = false
var _counts        : Dictionary = {}
var _sim_boost     : int   = 0
var _boost_ticks   : int   = 0


func _ready() -> void:
	_read_env()
	print("=== EventBus live shift tap ===")

	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return

	_protect = [
		"user://world_layout.json",
		"user://%s_save.json" % _slot,
		"user://%s_factory.json" % _slot,
	]
	_backup_files()

	var bus := get_node_or_null("/root/EventBus")
	bus.set_meta("pending_save_name", _slot)
	bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load")
		_finish(2)
		return
	_world = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()
		print("[tap] AutosaveTimer stopped")

	_clock = _world.get("shift_clock")
	if _clock == null:
		print("FATAL: no shift_clock on MainWorld")
		_finish(2)
		return

	# Decouple wall-clock compression from process time. The shipped default of
	# 24 means one real second is 24 shift-seconds but only 1 second of extruder
	# time, so an "8 hour shift" would give the machines 20 minutes of process.
	# At 1.0 a shift second IS a process second and the two agree.
	if "time_scale" in _clock:
		print("[tap] ShiftClock.time_scale %.1f -> %.1f"
			% [float(_clock.get("time_scale")), _shift_scale])
		_clock.set("time_scale", _shift_scale)

	if _clock.has_method("seek_to_wall_time"):
		_clock.call("seek_to_wall_time", _start_hh, _start_mm, false)
		print("[tap] clock seeked to %02d:%02d" % [_start_hh, _start_mm])
	for _i in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	_connect_all(bus)
	if OS.get_environment("TAP_ATTACH_BRAIN") != "":
		_attach_brains()
	_find_extruders()
	if _clock.has_signal("shift_ended"):
		_clock.shift_ended.connect(func(): _ended = true)
	var st := get_node_or_null("/root/SimTick")
	if st != null and not _extruders.is_empty():
		st.sim_tick.connect(_operator_tick)

	Engine.time_scale = _accel
	_shift_at_start = _shift_elapsed()
	_t_start_wall = float(Time.get_ticks_msec()) / 1000.0
	print("[tap] recording — accel=%.1fx budget=%.0fs" % [_accel, _max_wall_s])

	await _run()
	_write_all()
	_finish(0)


# ── the missing human ────────────────────────────────────────────────────────
# ExtruderMachine is driven ENTIRELY by the player: `_unhandled_input` writes
# into `_pending` when E is pressed, and nothing else ever starts a line. A
# headless shift therefore has no operator and the plant sits dark — the 90 s
# probe recorded exactly zero events.
#
# So the tap supplies an operator, writing into the SAME `_pending` dictionary
# the E key writes to. Nothing about the machine, LineFlow, the crew or the
# clock is stubbed; only the hand on the button is synthetic. Every action is
# an independent per-tick coin flip, so no structure is smuggled in through the
# operator's own behaviour.
var _extruders : Array = []
var _rng := RandomNumberGenerator.new()

const P_START      := 0.004
const P_STOP       := 0.00012
const P_VAC_LOST   := 0.00035
const P_VAC_RESTORE:= 0.0012
const P_CLEAR      := 0.004
const P_ESTOP_RESET:= 0.01

## Attach the sim brain the configured world never spawns.
##
## MEASURED, not assumed: a booted MainWorld on a real 84-placeable save has
## 8872 nodes across 67 scripts and ZERO ExtruderMachine.gd. The extruders in a
## built factory are geometry from PlaceableCatalog._m_extruder_unit(); the only
## thing that ever constructs an ExtruderModel is ExtruderMachine.gd:54, which
## lives solely on Extruder3B.tscn, which is instantiated solely by
## ExtruderGauntlet.gd (the bench) and LegacyPropsSpawner.gd — and the latter is
## gated behind `not WorldLayout.is_configured()`, so it is skipped for every
## real save ("[MainWorld] WorldLayout is authoritative").
##
## With TAP_ATTACH_BRAIN set, the tap does the wiring itself: one Extruder3B
## brain per placed extruder geometry, co-located, mesh hidden. This is a
## PROTOTYPE of the missing link, not a fix — it is here so a shift can be
## recorded at all, and so the recording shows what the plant would emit once
## the brain is wired for real.
func _attach_brains() -> void:
	var scn := load("res://src/scenes/machines/Extruder3B.tscn") as PackedScene
	if scn == null:
		print("[tap] Extruder3B.tscn missing — cannot attach brains")
		return
	var spots: Array = []
	for n in _world.find_children("*", "Node3D", true, false):
		if String(n.name).to_lower().contains("extruder") \
				and not String(n.name).to_lower().contains("silo"):
			spots.append(n)
	if spots.is_empty():
		spots.append(_world)
	var made := 0
	for spot in spots:
		var brain := scn.instantiate() as Node3D
		brain.name = "TapExtruderBrain%d" % made
		# Every Extruder3B.tscn ships the same ExtruderConfig resource, so two
		# brains would both call themselves "3B" and the whole event stream
		# would be ambiguous about which line emitted what. Duplicate the
		# config and take the line id from the geometry it is standing on.
		var cfg = brain.get("config_resource")
		if cfg != null:
			var own = cfg.duplicate()
			var nm := String(spot.name).to_lower()
			var m := RegEx.create_from_string("(\\d[a-c])")
			var hit := m.search(nm)
			if hit != null:
				own.line_id = hit.get_string(1).to_upper()
			else:
				own.line_id = "L%d" % made
			own.display_name = "Extruder %s" % own.line_id
			brain.set("config_resource", own)
		_world.add_child(brain)
		if spot is Node3D and spot != _world:
			brain.global_position = (spot as Node3D).global_position
		var body := brain.get_node_or_null("Body/BodyMesh") as MeshInstance3D
		if body != null:
			body.visible = false
		var lbl := brain.get_node_or_null("DebugLabel") as Label3D
		if lbl != null:
			lbl.visible = false
		made += 1
	print("[tap] attached %d Extruder3B brain(s) to %d geometry spot(s)"
		% [made, spots.size()])
	print("[tap] PROTOTYPE wiring — see _attach_brains() docstring")


func _find_extruders() -> void:
	var by_script: Dictionary = {}
	var total := 0
	for n in _world.find_children("*", "", true, false):
		total += 1
		var scr = n.get_script()
		if scr == null:
			continue
		var p := String(scr.resource_path).get_file()
		by_script[p] = int(by_script.get(p, 0)) + 1
		if p == "ExtruderMachine.gd":
			_extruders.append(n)
	print("[tap] found %d real extruder(s) in MainWorld" % _extruders.size())
	if OS.get_environment("TAP_DUMP_SCRIPTS") != "":
		print("[tap] %d nodes under MainWorld, %d distinct scripts:"
			% [total, by_script.size()])
		var keys := by_script.keys()
		keys.sort_custom(func(a, b): return int(by_script[a]) > int(by_script[b]))
		for k in keys:
			print("[tap]   %5d  %s" % [int(by_script[k]), k])
		print("[tap] WorldLayout.is_configured() = %s"
			% str(get_node("/root/WorldLayout").call("is_configured")))

func _operator_tick(_delta: float) -> void:
	for m in _extruders:
		var pend = m.get("_pending")
		var model = m.get("model")
		if pend == null or model == null:
			continue
		var st := int(model.get("state"))
		match st:
			0, 1:                                    # OFF, IDLE
				if _rng.randf() < P_START:
					pend["start_production"] = true
			8:                                       # PREHEAT
				# A real operator stands there waiting for the block to go
				# green and then presses. Pressing early is harmless — the
				# model ignores it until preheat_ready() — so this is just a
				# repeated press, not knowledge the operator would not have.
				if _rng.randf() < P_START:
					pend["start_production"] = true
			3:                                       # RUNNING
				if _rng.randf() < P_VAC_LOST:
					pend["vacuum_lost"] = true
				elif _rng.randf() < P_STOP:
					pend["stop_production"] = true
			5:                                       # VACUUM_ALARM
				if _rng.randf() < P_VAC_RESTORE:
					pend["vacuum_restored"] = true
			6:                                       # FAULT
				if _rng.randf() < P_CLEAR:
					pend["operator_clear_fault"] = true
			7:                                       # EMERGENCY_STOP
				if _rng.randf() < P_ESTOP_RESET:
					pend["reset_after_estop"] = true


func _read_env() -> void:
	var e := OS.get_environment("TAP_OUT")
	if e != "":
		_out_dir = e
	e = OS.get_environment("TAP_ACCEL")
	if e != "":
		_accel = float(e)
	e = OS.get_environment("TAP_SHIFT_SCALE")
	if e != "":
		_shift_scale = float(e)
	e = OS.get_environment("TAP_MAX_WALL_S")
	if e != "":
		_max_wall_s = float(e)
	e = OS.get_environment("TAP_SLOT")
	if e != "":
		_slot = e
	e = OS.get_environment("TAP_SIM_BOOST")
	if e != "":
		_sim_boost = int(e)
	e = OS.get_environment("TAP_START_HH")
	if e != "":
		_start_hh = int(e)
	e = OS.get_environment("TAP_START_MM")
	if e != "":
		_start_mm = int(e)


# ── generic signal capture ───────────────────────────────────────────────────
# Arity is not known until runtime and GDScript signals require an exact match,
# so there is one handler per arity and the signal name rides in on bind().
func _connect_all(bus: Node) -> void:
	var n := 0
	for sig in bus.get_signal_list():
		var name: String = sig["name"]
		if name.begins_with("script_") or name == "changed":
			continue
		var argc: int = (sig["args"] as Array).size()
		var cb: Callable
		match argc:
			0: cb = Callable(self, "_h0").bind(name)
			1: cb = Callable(self, "_h1").bind(name)
			2: cb = Callable(self, "_h2").bind(name)
			3: cb = Callable(self, "_h3").bind(name)
			4: cb = Callable(self, "_h4").bind(name)
			_: continue
		bus.connect(name, cb)
		n += 1
	print("[tap] connected to %d EventBus signals" % n)


func _h0(n: String) -> void: _log(n, [])
func _h1(a, n: String) -> void: _log(n, [a])
func _h2(a, b, n: String) -> void: _log(n, [a, b])
func _h3(a, b, c, n: String) -> void: _log(n, [a, b, c])
func _h4(a, b, c, d, n: String) -> void: _log(n, [a, b, c, d])


func _log(sig_name: String, args: Array) -> void:
	var shift_s := _shift_elapsed()
	var pretty: Array = []
	for a in args:
		pretty.append(_fmt(a))
	_events.append({
		"shift_s": shift_s,
		"time": _clock.get_time_string() if _clock.has_method("get_time_string") else "",
		"signal": sig_name,
		"args": pretty,
	})
	var sym := _symbol(sig_name, pretty)
	_stream.append(sym)
	_counts[sym] = int(_counts.get(sym, 0)) + 1


## The symbol is the part a human reading a SCADA journal would call "the event
## kind". Bare signal names are too coarse for the two channels that carry a
## discriminator in their payload: every state change and every scada_event
## would otherwise collapse into one token and the sequence would say nothing.
func _symbol(sig_name: String, args: Array) -> String:
	match sig_name:
		"machine_state_changed":
			if args.size() >= 3:
				return "state %s %s to %s" % [args[0], args[1], args[2]]
		"scada_event":
			if args.size() >= 2:
				return "scada %s %s" % [args[0], args[1]]
		"machine_alarm_raised", "machine_alarm_cleared":
			if args.size() >= 2:
				return "%s %s %s" % [sig_name, args[0], args[1]]
		"operator_mode_changed":
			if args.size() >= 2:
				return "mode %s to %s" % [args[0], args[1]]
	return sig_name


func _fmt(v) -> String:
	if v is Node:
		return String(v.name)
	if v is Dictionary:
		var keys := (v as Dictionary).keys()
		keys.sort()
		return "{%s}" % ",".join(PackedStringArray(keys.map(func(k): return str(k))))
	if v is float:
		return "%.3f" % v
	var s := str(v)
	return s.substr(0, 48) if s.length() > 48 else s


func _shift_elapsed() -> float:
	if _clock != null and "shift_elapsed_seconds" in _clock:
		return float(_clock.get("shift_elapsed_seconds"))
	return 0.0


# ── run loop ─────────────────────────────────────────────────────────────────
func _run() -> void:
	var last_report := 0.0
	while true:
		await get_tree().process_frame
		_frames += 1
		var wall := float(Time.get_ticks_msec()) / 1000.0 - _t_start_wall
		if _ended:
			print("[tap] shift_ended fired after %.0fs wall" % wall)
			return
		if wall >= _max_wall_s:
			print("[tap] wall budget reached (%.0fs)" % wall)
			return
		if wall - last_report >= 30.0:
			last_report = wall
			var shift := _shift_elapsed() - _shift_at_start
			print("[tap] wall=%4.0fs shift=%6.0fs (%s)  events=%d  fps=%.0f"
				% [wall, shift,
				   _clock.get_time_string() if _clock.has_method("get_time_string") else "?",
				   _events.size(), float(_frames) / maxf(wall, 0.001)])


func _write_all() -> void:
	var abs_dir := ProjectSettings.globalize_path(_out_dir)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	var f := FileAccess.open(_out_dir.path_join("events.jsonl"), FileAccess.WRITE)
	for e in _events:
		f.store_line(JSON.stringify(e))
	f.close()

	f = FileAccess.open(_out_dir.path_join("stream.log"), FileAccess.WRITE)
	for s in _stream:
		f.store_line(s)
	f.close()

	var wall := float(Time.get_ticks_msec()) / 1000.0 - _t_start_wall
	var shift := _shift_elapsed() - _shift_at_start
	# Physics drift: how far the physics clock fell behind the process clock.
	# 1.0 means the crew kept up with the machines; below that, NPC-driven
	# events are under-represented relative to machine events.
	var expected_phys := shift * float(Engine.physics_ticks_per_second)
	var drift := (float(_physics_frames) / expected_phys) if expected_phys > 0 else 1.0

	var lines: Array[String] = []
	lines.append("wall_s        %.1f" % wall)
	lines.append("shift_s       %.1f  (%.2f x real time)" % [shift, shift / maxf(wall, 0.001)])
	lines.append("frames        %d  (%.0f fps)" % [_frames, float(_frames) / maxf(wall, 0.001)])
	lines.append("physics_ratio %.3f  (1.0 = crew kept pace with the machines)" % drift)
	var proc_s := 0.1 * float(_boost_ticks) + shift
	lines.append("sim_boost     %d extra ticks/frame, %d ticks total"
		% [_sim_boost, _boost_ticks])
	lines.append("process_s     %.0f  (%.1fx the shift clock)"
		% [proc_s, proc_s / maxf(shift, 0.001)])
	lines.append("              machine events are over-represented vs crew")
	lines.append("              events by that factor -- do not read the two rates")
	lines.append("              against each other without dividing it out")
	lines.append("events        %d  (%.2f per shift-minute)"
		% [_events.size(), 60.0 * float(_events.size()) / maxf(shift, 0.001)])
	lines.append("distinct      %d" % _counts.size())
	lines.append("")
	var keys := _counts.keys()
	keys.sort_custom(func(a, b): return int(_counts[a]) > int(_counts[b]))
	for k in keys:
		lines.append("%7d  %s" % [int(_counts[k]), k])

	f = FileAccess.open(_out_dir.path_join("summary.txt"), FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()

	for l in lines:
		print("[sum] " + l)
	print("[tap] wrote %d events to %s" % [_events.size(), abs_dir])


func _physics_process(_d: float) -> void:
	_physics_frames += 1


## Process-sim acceleration, applied ONLY to SimTick.
##
## Engine.time_scale is the wrong lever: it scales physics too, and Godot caps
## physics catch-up at max_physics_steps_per_frame, so the crew ends up walking
## in slow motion relative to the machines. SimTick is a plain accumulator
## driven by _process and capped at 1 s of catch-up per frame, which pins the
## process sim to roughly real time no matter what time_scale says. Emitting
## extra ticks advances the machines and nothing else, which is exactly the
## trade this run wants — and it is reported, not hidden: `boost_ticks` and the
## resulting process:shift ratio go in summary.txt so nobody reads the machine
## event rate as if the crew had kept up.
func _process(_d: float) -> void:
	if _sim_boost <= 0:
		return
	var st := get_node_or_null("/root/SimTick")
	if st == null:
		return
	for _i in range(_sim_boost):
		st.sim_tick.emit(0.1)
		_boost_ticks += 1


# ── file protection (the reference harness declared this and never wrote it) ──
func _backup_files() -> void:
	for p in _protect:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				_backups[p] = f.get_buffer(f.get_length())
				f.close()

func _restore_files() -> void:
	for p in _protect:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(data)
				f.close()

func _finish(code: int) -> void:
	Engine.time_scale = 1.0
	_restore_files()
	print("[tap] done (exit %d)" % code)
	get_tree().quit(code)
