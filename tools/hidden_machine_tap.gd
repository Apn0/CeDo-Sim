extends SceneTree

## Headless tap: drives the REAL ExtruderModel with a memoryless operator policy
## and writes two symbol streams to disk for external causal-state analysis.
##
## Why memoryless inputs: if the operator policy had memory of its own, any
## structure recovered downstream could be the POLICY's structure rather than
## the MODEL's. Every input here is an independent per-tick coin flip, so all
## recovered memory provably belongs to ExtruderModel.
##
##   events.log     — one line per emitted event. This is what a real SCADA
##                    event journal looks like: sparse, timing discarded.
##   historian_<K>.log — one line per K sim-ticks, always. This is what a real
##                    process historian looks like: fixed cadence, so the
##                    120 s vacuum grace survives as a run of ALARM samples.
##
## Run:
##   godot --headless --path <proj> --script res://tools/hidden_machine_tap.gd
## Optional env: HM_TICKS, HM_SEED, HM_OUT, HM_SAMPLE_TICKS

const TICK_DT := 0.1  # matches SimTick.TICK_DT (10 Hz)

const STATE_NAME := {
	0: "OFF", 1: "IDLE", 2: "STARTING", 3: "RUNNING",
	4: "STOPPING", 5: "VACUUM_ALARM", 6: "FAULT", 7: "EMERGENCY_STOP",
}

func _initialize() -> void:
	var ticks := int(_env("HM_TICKS", "600000"))
	var seed_v := int(_env("HM_SEED", "12345"))
	# Several historian cadences in one pass. The 120 s vacuum grace spans
	# 120/(K*0.1) samples, so K decides whether the mechanism can fit inside a
	# reconstruction window at all: K=50 -> 24 samples, K=800 -> 1.5 samples.
	var cadences := [50, 100, 200, 400, 800]
	var out_dir := _env("HM_OUT", "user://hidden_machine")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v

	var cfg := ExtruderConfig.new()
	var model := ExtruderModel.new(cfg)

	# --- harness scaffolding, NOT model logic (declared so nothing is smuggled) --
	# ExtruderModel starts melt_temp at ambient 25 C and _tick_off actively cools
	# toward 25. Cold melt costs (215-25) * 2 %/C = 380 % extra motor torque against
	# a 110 % trip, so a cold line trips 2 s into every start and never reaches
	# RUNNING. That is correct physics for a cold extruder; it just means the model
	# assumes the zone heaters are somebody else's job. A real line at shift change
	# has been hot for days, so the harness holds the melt at setpoint whenever the
	# screw is not yet under load. This is a plant fact, not an operator decision:
	# no input to the model is gated on model state, so every operator action below
	# stays an independent coin flip.
	var heater_states := [0, 1, 2]  # OFF, IDLE, STARTING
	model.melt_temp = cfg.melt_temp_setpoint

	# Plain Arrays, not PackedStringArray-in-Dictionary: packed arrays are value
	# types, so `dict[k].append(x)` would mutate a temporary copy and silently
	# write empty files. Arrays are reference types and survive the lookup.
	var ev_lines: Array = []
	var hist: Array = []
	for _k in cadences:
		hist.append([])

	# Per-tick probabilities. Tuned so the line spends most of its time RUNNING
	# but visits the vacuum cascade often enough to estimate it (the grace is
	# 120 s = 1200 ticks, so p(vacuum_lost) must be small or the line never runs).
	var p_start := 0.004
	var p_stop := 0.00012
	var p_vacuum_lost := 0.00035
	var p_vacuum_restored := 0.0012
	var p_clear_fault := 0.004
	var p_estop := 0.000004
	var p_reset_estop := 0.01

	var grace_ticks := int(cfg.vacuum_alarm_grace_s / TICK_DT)
	print("[tap] grace=%.0fs (%d ticks), %d sim-ticks requested"
		% [cfg.vacuum_alarm_grace_s, grace_ticks, ticks])

	var state_hist := {}
	for t in range(ticks):
		var inputs := {
			"start_production": rng.randf() < p_start,
			"stop_production": rng.randf() < p_stop,
			"vacuum_lost": rng.randf() < p_vacuum_lost,
			"vacuum_restored": rng.randf() < p_vacuum_restored,
			"operator_clear_fault": rng.randf() < p_clear_fault,
			"emergency_stop": rng.randf() < p_estop,
			"reset_after_estop": rng.randf() < p_reset_estop,
		}
		var events: Array = model.tick(TICK_DT, inputs)
		for e in events:
			ev_lines.append(_normalise_event(String(e)))

		var st := int(model.state)
		if st in heater_states:
			model.melt_temp = maxf(model.melt_temp, cfg.melt_temp_setpoint - 2.0)
		state_hist[st] = int(state_hist.get(st, 0)) + 1
		var sname: String = STATE_NAME.get(st, "S%d" % st)
		for i in range(cadences.size()):
			if t % int(cadences[i]) == 0:
				hist[i].append(sname)

	_write(out_dir.path_join("events.log"), ev_lines)
	print("[tap] events=%d" % ev_lines.size())
	for i in range(cadences.size()):
		var k: int = int(cadences[i])
		var secs: int = int(round(float(k) * TICK_DT))
		_write(out_dir.path_join("historian_%ds.log" % secs), hist[i])
		print("[tap] historian %3ds cadence : %7d samples, grace spans %.1f samples"
			% [secs, hist[i].size(), cfg.vacuum_alarm_grace_s / (float(k) * TICK_DT)])
	var total := 0
	for k in state_hist:
		total += int(state_hist[k])
	for k in state_hist:
		print("[tap] state %-16s %7d ticks (%5.2f%%)"
			% [STATE_NAME.get(k, str(k)), state_hist[k], 100.0 * float(state_hist[k]) / float(total)])
	print("[tap] wrote to %s" % ProjectSettings.globalize_path(out_dir))
	quit(0)

## state_changed:<old>:<new> carries the numeric states. Rewrite it to named
## form so the external tool sees the same token a human reading a SCADA
## journal would see — and so nothing depends on Godot's enum ordering.
func _normalise_event(e: String) -> String:
	if e.begins_with("state_changed:"):
		var parts := e.split(":")
		if parts.size() == 3:
			return "state_changed %s to %s" % [
				STATE_NAME.get(int(parts[1]), parts[1]),
				STATE_NAME.get(int(parts[2]), parts[2]),
			]
	return e

func _write(path: String, lines: Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write %s" % path)
		return
	for l in lines:
		f.store_line(l)
	f.close()

func _env(key: String, fallback: String) -> String:
	var v := OS.get_environment(key)
	return v if v != "" else fallback
