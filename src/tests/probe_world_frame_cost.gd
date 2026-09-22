extends Node
## PROBE (2026-09-23) — per-frame CPU cost of a booted MainWorld, headless.
## Boots the real world on the operator's world_layout.json (read only; backed
## up and byte-compared at the end), lets it settle, then samples the engine's
## own monitors over SAMPLE_FRAMES frames:
##   TIME_PROCESS / TIME_PHYSICS_PROCESS  — script + engine work per frame (s)
##   OBJECT_NODE_COUNT, OBJECT_ORPHAN_NODE_COUNT, MEMORY_STATIC
## and prints min / mean / max. Headless means NO rendering cost is in here —
## this is the simulation + scripting side only, which is exactly the part a
## code change can move. Numbers are printed, not asserted (a measurement, not
## a gate). Not wired in run.sh.
##
##   godot --headless --path . res://src/tests/probe_world_frame_cost.tscn

const TEST_SLOT := "__framecost__"
const BOOT_FRAMES := 120
const SAMPLE_FRAMES := 300
const WATCHDOG_S := 300.0
const PROTECT := ["user://world_layout.json"]

var _backups : Dictionary = {}

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

func _slurp(p: String) -> PackedByteArray:
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func _stats(a: Array) -> String:
	if a.is_empty():
		return "n/a"
	var lo : float = a[0]
	var hi : float = a[0]
	var sum := 0.0
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	return "min %.3f  mean %.3f  max %.3f" % [lo, sum / a.size(), hi]

func _run() -> void:
	print("[PROBE] world frame cost (headless)")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	for p in PROTECT:
		_backups[p] = _slurp(p)
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	var t_boot0 := Time.get_ticks_msec()
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	var t_boot1 := Time.get_ticks_msec()
	print("  info  : boot + %d settle frames: %d ms" % [BOOT_FRAMES, t_boot1 - t_boot0])

	var proc_ms : Array = []
	var phys_ms : Array = []
	var frame_ms : Array = []
	var last := Time.get_ticks_usec()
	for _i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	print("  info  : over %d frames — TIME_PROCESS ms/frame: %s" % [SAMPLE_FRAMES, _stats(proc_ms)])
	print("  info  : over %d frames — TIME_PHYSICS_PROCESS ms/frame: %s" % [SAMPLE_FRAMES, _stats(phys_ms)])
	print("  info  : over %d frames — wall ms/frame (headless, includes idle): %s" % [SAMPLE_FRAMES, _stats(frame_ms)])
	print("  info  : nodes %d, orphan nodes %d, static memory %.1f MB, physics active objects %d"
		% [int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		   int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		   Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		   int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS))])
	# Script-level breakdown: which node classes are processing every frame.
	var per_class := {}
	for n in get_tree().root.find_children("*", "", true, false):
		if not (n is Node):
			continue
		var nn := n as Node
		if nn.is_processing() or nn.is_physics_processing():
			var k := nn.get_class()
			var scr = nn.get_script()
			if scr != null and scr is Script:
				var rp : String = (scr as Script).resource_path.get_file()
				if rp != "":
					k = rp
			per_class[k] = int(per_class.get(k, 0)) + 1
	var keys := per_class.keys()
	keys.sort_custom(func(a, b): return int(per_class[a]) > int(per_class[b]))
	var top : Array = []
	for i in mini(12, keys.size()):
		top.append("%s×%d" % [keys[i], per_class[keys[i]]])
	print("  info  : processing nodes by script/class (top 12): %s" % ", ".join(top))

	world.queue_free()
	await get_tree().process_frame
	var changed : Array = []
	for p in PROTECT:
		if _slurp(p) != _backups[p]:
			changed.append(p)
			var w := FileAccess.open(p, FileAccess.WRITE)
			if w != null:
				w.store_buffer(_backups[p])
				w.close()
	if not changed.is_empty():
		print("  note  : restored %s (changed during the probe)" % str(changed))
	print("Result: PASS (1 ok, 0 fail — measurement printed above)")
	get_tree().quit(0)
