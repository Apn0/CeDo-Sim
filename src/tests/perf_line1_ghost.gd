extends Node
# =============================================================================
# perf_line1_ghost — what does the whole-line placement ghost COST to draw?
# =============================================================================
# #linebuilder-geometry (2026-09-06) replaced ~50 footprint boxes with ~50 real
# machines, and shot_line1_ghost measured the result at 1433 MeshInstance3D.
# Ghosts skip StaticMerge (PlaceableCatalog.gd:1522), so every one of those parts
# is its own draw call. With the ghost up the PERF overlay read "FPS 2, avg 7,
# Draw calls 3462" — observed, never measured against a baseline, so the ghost
# was never actually shown to be the cause.
#
# A single DOWN -> UP -> DOWN pass is NOT enough, learned the hard way on the
# first run: the plant is still settling for a long time after boot, so sample 1
# read 132 ms and sample 3 read 50 ms with LESS in the scene than sample 1 had.
# The baseline drifts faster than the effect being measured. So this SETTLES
# first (waits for the rolling frame time to stop improving) and then
# INTERLEAVES A/B/A/B, which cancels whatever drift is left.
#
# Run WINDOWED. --headless renders nothing, so every counter would read 0:
#   Godot --path . res://src/tests/perf_line1_ghost.tscn
#
# PROTECT/restore copied from test_line_builder_ghost: booting MainWorld against
# a test slot writes user:// files, and on 2026-09-06 a damaged world_layout.json
# cost a full harness run of misleading reds.
# =============================================================================

const TEST_SLOT : String = "__line1ghostperf__"
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__line1ghostperf___save.json",
	"user://__line1ghostperf___factory.json",
]
const BOOT_FRAMES : int = 120
const WARM_FRAMES : int = 12     # discarded — frames right after a tree change are noise
const SAMPLE_FRAMES : int = 40   # short: the shorter a pair, the less drift can creep INTO it
const REPS : int = 6             # A/B pairs, differenced PAIRWISE (see the verdict block)
const SETTLE_WINDOW : int = 60
const SETTLE_MAX : int = 60      # windows, not frames — hard stop so a busy plant cannot hang the probe
const SETTLE_STABLE : int = 3    # consecutive low-drift windows required

var _backups : Dictionary = {}
var _world : Node3D = null

func _backup_files() -> void:
	for p in PROTECT:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in PROTECT:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(data)
			f.close()

func _finish(code: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)

## Average over SAMPLE_FRAMES real frames, after discarding WARM_FRAMES.
## Frame TIME is taken from the delta the tree actually reports, and the draw
## counters from RenderingServer, so nothing here is inferred from the other.
func _sample(label: String) -> Dictionary:
	for i in range(WARM_FRAMES):
		await get_tree().process_frame
	var total := 0.0
	var worst := 0.0
	var calls := 0
	var prims := 0
	for i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var dt : float = get_process_delta_time()
		total += dt
		worst = maxf(worst, dt)
		calls += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		prims += int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var avg_ms : float = (total / float(SAMPLE_FRAMES)) * 1000.0
	var out := {
		"label": label,
		"avg_ms": avg_ms,
		"fps": (1000.0 / avg_ms) if avg_ms > 0.0 else 0.0,
		"worst_ms": worst * 1000.0,
		"calls": int(float(calls) / float(SAMPLE_FRAMES)),
		"prims": int(float(prims) / float(SAMPLE_FRAMES)),
	}
	print("[PERF] %-22s avg %6.2f ms (%5.1f fps)  worst %6.2f ms  draw calls %5d  primitives %9d"
		% [label, out["avg_ms"], out["fps"], out["worst_ms"], out["calls"], out["prims"]])
	return out

## Wait until the plant stops getting faster on its own. Boot spawns crew,
## bakes nav and settles physics for a long time; measuring through that gives a
## baseline that drifts more than the ghost costs.
func _settle() -> void:
	var prev := INF
	var stable := 0
	for w in range(SETTLE_MAX):
		var t := 0.0
		for i in range(SETTLE_WINDOW):
			await get_tree().process_frame
			t += get_process_delta_time()
		var avg : float = (t / float(SETTLE_WINDOW)) * 1000.0
		var drift : float = absf(prev - avg) / maxf(avg, 0.001)
		# ONE quiet window is not settled: measured 2026-09-06, the plant hit 3.9%
		# drift at window 1 and then still fell from 133 ms to 60 ms afterwards.
		if drift < 0.04:
			stable += 1
		else:
			stable = 0
		print("[PERF] settling… window %2d avg %6.2f ms (drift %5.1f%%, stable %d/%d)"
			% [w, avg, drift * 100.0, stable, SETTLE_STABLE])
		if stable >= SETTLE_STABLE:
			print("[PERF] settled at %.2f ms after %d windows" % [avg, w + 1])
			return
		prev = avg
	print("[PERF] WARN: never settled within %d windows — the delta below carries that drift" % SETTLE_MAX)

func _mean(rows: Array, key: String) -> float:
	var t := 0.0
	for r in rows:
		t += float(r[key])
	return t / maxf(float(rows.size()), 1.0)

func _ready() -> void:
	print("=== perf_line1_ghost — cost of the whole-line placement ghost ===")
	if DisplayServer.get_name() == "headless":
		print("FATAL: run WINDOWED — headless renders nothing, every counter would read 0.")
		get_tree().quit(2); return
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	_backup_files()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	for i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var bm : Node = _world.get("build_mode")
	if bm == null:
		print("FATAL: world.build_mode is null"); _finish(1); return

	await _settle()

	var offs : Array = []
	var ons : Array = []
	var meshes := 0
	for rep in range(REPS):
		offs.append(await _sample("A%d no ghost" % (rep + 1)))

		bm.call("_spawn_ghost", "line_1")
		await get_tree().process_frame
		var ghost : Node3D = bm.get("_ghost") as Node3D
		if ghost == null:
			print("FATAL: _spawn_ghost produced no ghost"); _finish(1); return
		meshes = ghost.find_children("*", "MeshInstance3D", true, false).size()
		ons.append(await _sample("B%d ghost up (%d meshes)" % [rep + 1, meshes]))
		bm.call("_clear_ghost")
		await get_tree().process_frame

	# PAIRED differences. The baseline drifts (the plant keeps settling for
	# minutes), and drift between the START and END of the run is far larger than
	# the ghost costs — measured, +-36.59 ms of wobble against a -10 ms effect. But
	# each B sits directly after its own A, so B_i - A_i cancels almost all of it.
	# The spread of those deltas, not of the raw times, is the honest noise floor.
	var deltas : Array = []
	for i in range(offs.size()):
		deltas.append(float(ons[i]["avg_ms"]) - float(offs[i]["avg_ms"]))
	var d_ms := 0.0
	for d in deltas:
		d_ms += float(d)
	d_ms /= maxf(float(deltas.size()), 1.0)
	var sd := 0.0
	for d in deltas:
		sd += pow(float(d) - d_ms, 2.0)
	sd = sqrt(sd / maxf(float(deltas.size() - 1), 1.0))
	# MEDIAN, not the mean, decides. Measured 2026-09-06: the first two pairs of a
	# run read +55.1 and +46.2 ms while the last four read -0.7 / +0.6 / -2.6 /
	# +0.1 — the early As caught the plant before its frame time had pinned, so
	# those two pairs measure the baseline moving, not the ghost. Two outliers in
	# six drag the mean to +16 ms and invent a cost that is not there; the median
	# ignores them. sd is still printed, as the honest spread.
	var sorted_d : Array = deltas.duplicate()
	sorted_d.sort()
	var n : int = sorted_d.size()
	var med : float = float(sorted_d[n / 2]) if n % 2 == 1 		else (float(sorted_d[n / 2 - 1]) + float(sorted_d[n / 2])) * 0.5
	var off_calls : float = _mean(offs, "calls")
	var on_calls : float = _mean(ons, "calls")
	print("
--- attributable to the ghost (%d PAIRED A/B differences) ---" % deltas.size())
	var line := "  per-pair B-A:"
	for d in deltas:
		line += " %+.1f" % float(d)
	print(line + "  ms")
	print("  frame time  median %+.2f ms   mean %+.2f ms +- %.2f (1 sd)   [%.2f -> %.2f ms]"
		% [med, d_ms, sd, _mean(offs, "avg_ms"), _mean(ons, "avg_ms")])
	print("  draw calls  %+7.0f      (%.0f -> %.0f)" % [on_calls - off_calls, off_calls, on_calls])
	print("  primitives  %+7.0f" % [_mean(ons, "prims") - _mean(offs, "prims")])
	if absf(med) <= 3.0:
		print("  VERDICT: NOT MEASURABLE — median %+.2f ms over %d meshes and %+.0f"
			% [med, meshes, on_calls - off_calls])
		print("           draw calls. The scene is CPU-bound (scripts/physics), so")
		print("           the ghost's draw calls are not what costs frames. Do NOT")
		print("           StaticMerge the ghost to 'fix' this: it would buy nothing")
		print("           measurable and would break test_line_builder_ghost section")
		print("           5, whose box-vs-real discriminator IS the unmerged part count.")
	else:
		print("  VERDICT: ghost costs %+.2f ms median (%.4f ms/mesh over %d meshes)."
			% [med, med / maxf(float(meshes), 1.0), meshes])
	print("=========================================")
	_finish(0)
