extends Node

## #221 — Hotspot profiler for diagnosing the 7–11 FPS / 60–130 ms proc floor.
##
## What it does:
##   1) Censuses the live scene tree by script class_name → "how many of what".
##      This isolates "the tree is fat with X" from "X is expensive per node".
##   2) Asks SimTick to self-time each tick.emit() (see SimTick.probe_sim_tick).
##      If sim_tick avg ≈ proc_ms, the line+plant model is the floor; if it's
##      small, the cost lives in _process / _physics_process work on nodes.
##   3) Counts physics bodies + named groups (belts, vehicles, NPCs, bales,
##      MultiMesh instances, AudioStreamPlayer3D, lights) — the "fat tree"
##      categories. Each is a separate per-frame O(n) update somewhere.
##   4) Prints a "[HOTSPOT]" block to the console once per LOG_INTERVAL_S so it
##      sits next to the existing [PERF] line in the log.
##
## Toggle with F7 (default OFF — we don't want this overhead in normal play).
## When OFF the autoload sits idle (process disabled) and SimTick stops timing.
##
## (F4 is the player camera-mode cycle — reserved. F3=PerfHud, F8=InspectMode,
## F10=feedback capture, F11=door capture; F5=freecam_save. F7 is free.)

const LOG_INTERVAL_S : float = 5.0
const TOP_N          : int   = 15

var _enabled    : bool  = false
var _log_accum  : float = 0.0
# Track group-add hooks lazily; the groups themselves may not exist at boot.
var _known_groups : PackedStringArray = PackedStringArray([
	"placed_object", "belt", "vehicle", "bale", "machine_leg",
	"lump_cart", "rotating_mechanism", "plant_audio", "interactable", "yards",
])

func _ready() -> void:
	# Survive scene changes (autoload always does, but be explicit).
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)
	set_process_input(true)
	print("[HOTSPOT] ready — F7 to toggle. Off by default. Logs every %.0fs when on." % LOG_INTERVAL_S)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F7:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	_enabled = not _enabled
	set_process(_enabled)
	if has_node("/root/SimTick"):
		SimTick.probe_sim_tick = _enabled
		if _enabled:
			SimTick.avg_emit_us = 0.0
			SimTick.last_emit_us = 0
	_log_accum = 0.0
	if _enabled:
		print("[HOTSPOT] enabled — first census in %.0fs" % LOG_INTERVAL_S)
		# Immediate snapshot so the operator gets one without waiting.
		_dump_report()
	else:
		print("[HOTSPOT] disabled")

func _process(delta: float) -> void:
	_log_accum += delta
	if _log_accum >= LOG_INTERVAL_S:
		_log_accum = 0.0
		_dump_report()

# ─────────────────────────────────────────────────────────────────────────────
# Census + report.
# ─────────────────────────────────────────────────────────────────────────────
func _dump_report() -> void:
	var t0 : int = Time.get_ticks_usec()

	# 1) Walk the tree once. Bucket by script + per-category counts.
	var by_script : Dictionary = {}     # String -> int
	# Dictionary so counters survive recursion (ints are value-typed in GDScript).
	var c : Dictionary = {
		"proc": 0, "phys": 0, "rigid": 0, "char": 0, "static": 0,
		"area": 0, "joint": 0, "mm": 0, "mm_inst": 0, "audio": 0,
		"light": 0, "vis": 0, "total": 0,
	}
	_walk2(get_tree().root, by_script, c)

	# 2) Named-group counts (cheap, group hashes maintained by SceneTree).
	var grp : Dictionary = {}
	for g in _known_groups:
		grp[g] = get_tree().get_nodes_in_group(g).size()

	# 3) Top-N by script.
	var pairs : Array = []
	for k in by_script.keys():
		pairs.append([k, int(by_script[k])])
	pairs.sort_custom(func(a, b): return a[1] > b[1])

	# 4) Build & emit report.
	var lines : Array[String] = []
	lines.append("[HOTSPOT] ── snapshot ──────────────────────────────────────────────────")
	if has_node("/root/SimTick"):
		var emit_ms_avg  : float = float(SimTick.avg_emit_us) / 1000.0
		var emit_ms_last : float = float(SimTick.last_emit_us) / 1000.0
		var subs : int = SimTick.subscriber_count()
		# ms/emit × emits/s = ms of CPU per real-time second. /10 → percent of a
		# 1000 ms budget. (Works out to emit_ms_avg × 1.0 at 10 Hz, but the
		# expression stays correct if TICK_HZ ever changes.)
		var emit_load_pct : float = emit_ms_avg * SimTick.TICK_HZ / 10.0
		lines.append("[HOTSPOT] sim_tick: avg=%.2fms last=%.2fms × %.0f/s ≈ %.1f%% of CPU | subs=%d" % [
			emit_ms_avg, emit_ms_last, SimTick.TICK_HZ, emit_load_pct, subs])
	lines.append("[HOTSPOT] tree: total=%d   _process=%d   _physics_process=%d   visible=%d" % [
		c["total"], c["proc"], c["phys"], c["vis"]])
	lines.append("[HOTSPOT] physics: rigid=%d char=%d static=%d area=%d joints=%d" % [
		c["rigid"], c["char"], c["static"], c["area"], c["joint"]])
	lines.append("[HOTSPOT] render: mm_nodes=%d mm_instances=%d audio3d=%d lights=%d" % [
		c["mm"], c["mm_inst"], c["audio"], c["light"]])
	var grp_line := "[HOTSPOT] groups:"
	for g in _known_groups:
		grp_line += "  %s=%d" % [g, int(grp[g])]
	lines.append(grp_line)
	lines.append("[HOTSPOT] top scripts by node count:")
	var shown : int = 0
	for p in pairs:
		if shown >= TOP_N: break
		# `nm` not `name` — Node.name is reserved and shadowing it triggers a warning.
		var nm : String = String(p[0])
		var n  : int    = int(p[1])
		lines.append("[HOTSPOT]   %-44s × %5d" % [nm, n])
		shown += 1
	var dt_us : int = Time.get_ticks_usec() - t0
	lines.append("[HOTSPOT] (census took %.1fms)" % (float(dt_us) / 1000.0))
	for line in lines:
		print(line)

# Single-pass tree walk that maintains its counters inside a Dictionary `c`
# (which is passed by reference, unlike ints) and a script-frequency Dict.
func _walk2(node: Node, by_script: Dictionary, c: Dictionary) -> void:
	c["total"] += 1
	if node is Node3D:
		if (node as Node3D).visible:
			c["vis"] += 1
	# _process / _physics_process detection. has_method() returns true for
	# both inherited & overridden, but if the script doesn't override these,
	# they're the base no-op and have no per-frame cost — except that Godot
	# only calls them when the node has set_process(true). We approximate
	# "actually being processed" via is_processing() / is_physics_processing().
	if node.is_processing():
		c["proc"] += 1
	if node.is_physics_processing():
		c["phys"] += 1
	# Physics class bucketing.
	if node is RigidBody3D:                c["rigid"]  += 1
	elif node is CharacterBody3D:          c["char"]   += 1
	elif node is StaticBody3D:             c["static"] += 1
	elif node is Area3D:                   c["area"]   += 1
	elif node is Joint3D:                  c["joint"]  += 1
	# Render-side bucketing.
	if node is MultiMeshInstance3D:
		c["mm"] += 1
		var mm : MultiMesh = (node as MultiMeshInstance3D).multimesh
		if mm != null:
			c["mm_inst"] += mm.instance_count
	elif node is AudioStreamPlayer3D:      c["audio"]  += 1
	elif node is Light3D:                  c["light"]  += 1
	# Script bucketing.
	var s : Script = node.get_script() as Script
	if s != null:
		var nm : String = _script_label(s)
		by_script[nm] = int(by_script.get(nm, 0)) + 1
	for ch in node.get_children():
		_walk2(ch, by_script, c)

# Best-available label for a Script instance. Prefers class_name; falls back to
# the resource path's basename (e.g. "BeltSurface" from "res://.../BeltSurface.gd").
func _script_label(s: Script) -> String:
	if s == null: return "?"
	# Godot 4: GDScript exposes get_global_name() since 4.3.
	if s.has_method("get_global_name"):
		var gn : String = String(s.call("get_global_name"))
		if gn != "": return gn
	var p : String = s.resource_path
	if p == "": return "?inline?"
	# strip "res://" prefix and ".gd" suffix.
	var idx : int = p.rfind("/")
	var leaf : String = p.substr(idx + 1) if idx >= 0 else p
	if leaf.ends_with(".gd"): leaf = leaf.substr(0, leaf.length() - 3)
	return leaf
