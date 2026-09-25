extends Node
## MACHINE SOUNDS (2026-09-25) — the operator's recordings, placed on the
## machines they were made at, and driven by the sim's own state.
##
##   godot --headless --path . res://src/tests/test_machine_sounds.tscn
##
## What is proven, section by section (the operator's own rules in quotes):
##   S1  every MachineSoundSpec .tres loads, and every WAV it names exists as
##       16-bit stereo 44.1 kHz PCM (the format the crossfade and the mix need),
##       loops looping, one-shots not.
##   S2  build_node attaches the sound by id — data-driven, idempotent, never on
##       a ghost, never on a machine without a .tres.
##   S3  "if machine is not operating at all → no sound": the players are
##       STOPPED at drive 0. "during ramp-up/down the audio will be different":
##       pitch and level follow the drive between the spec's floor and 1.0, and
##       a spec ramp_down_s longer than the sim's spin-down is honoured. The
##       driver watchdog winds a machine down when nobody drives it.
##   S4  LineFlow drives it: a hand-mode ON node ramps its sound to full over
##       SPIN_UP_S, and OFF ramps it back to 0 — the sound reads `spin`, never
##       `powered`, so it is heard at the speed the machine is AT.
##   S5  the leaf blower: start clip on the OFF→SPOOLING_UP edge, idle loop at
##       low spool, the rev loop taking over at full spool, stop clip at OFF.
##   S6  the valve crank: hose-reel base valve (open/open/close cycle) and the
##       IBC tote drain, one event each.
##   S7  the compactor: the 1:11-1:14 window played three times is its RUN
##       LOOP ("that entire sound of the three, in a sequence, has to loop"),
##       8.91 s, LOOP_FORWARD, pitch pinned at 1.0 — air pulses do not
##       pitch-bend with motor speed — and stopped, not quiet, at drive 0.
##   S8  the wash-line panel beeps on an unacknowledged wash-line alarm, stops
##       on KWITTEREN, ignores another line's alarm, stops when it clears, and
##       counts the overlay's scoped faults the same way.
##
## Headless: AudioStreamPlayer3D runs on the dummy driver, so `playing`, pitch
## and volume are real. Nothing here asserts on audio CONTENT (Trap: a headless
## suite cannot read a mixed buffer).

const WATCHDOG_S : float = 240.0
const TICK_S     : float = 0.1

const BankScript  := preload("res://src/audio/MachineSoundBank.gd")
const SpecScript  := preload("res://src/audio/MachineSoundSpec.gd")
const HmiScript   := preload("res://src/build/Hmi.gd")
const OVERLAY_SCENE := "res://src/scenes/hud/HmiOverlay.tscn"

var _fails : int = 0
var _oks   : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

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

# ── helpers ───────────────────────────────────────────────────────────────────
func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

## Keep calling set_drive(level) every frame for `s` seconds (the component's
## driver watchdog drops the target after 1 s of silence, as LineFlow would).
func _hold(snd: Node, level: float, s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		snd.call("set_drive", level)
		await get_tree().process_frame

func _wav_info(path: String) -> Dictionary:
	var st := load(path)
	if not (st is AudioStreamWAV):
		return {"ok": false, "why": "not an AudioStreamWAV (%s)" % [st]}
	var w := st as AudioStreamWAV
	return {"ok": w.format == AudioStreamWAV.FORMAT_16_BITS and w.stereo and w.mix_rate == 44100,
		"format": w.format, "stereo": w.stereo, "rate": w.mix_rate,
		"loop": w.loop_mode, "frames": (w.data.size() / 4) if w.format == AudioStreamWAV.FORMAT_16_BITS else 0}

## Free an in-tree body the physics server may still hold events for (its
## Area3D triggers): queue it and let two frames pass. An immediate free() here
## made godot_rapier print "Expected Area" from its collision callback.
func _free_body(n: Node) -> void:
	if n == null:
		return
	n.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _node_index_by_id(nodes: Array, id: String) -> int:
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == id:
			return i
	return -1

# ── the run ───────────────────────────────────────────────────────────────────
func _run() -> void:
	print("[TEST] machine sounds — operator recordings on their machines, driven by the sim")
	await _s1_specs()
	await _s2_attach()
	await _s3_drive()
	await _s4_lineflow()
	await _s5_leafblower()
	await _s6_valves()
	await _s7_compactor()
	await _s8_wash_alarm()
	_finish()

func _s1_specs() -> void:
	print("-- S1: specs and clips")
	var ids : Array = BankScript.spec_ids()
	_check(ids.size() >= 12, "S1 %d sound specs on disk: %s" % [ids.size(), ids])
	var expected := ["trilzeef", "laser_filter", "mech_dryer", "blower", "verdeelwals", "plasmaq",
		"shredder_2", "compactor", "tool_leafblower", "hose_reel_valve", "ibc_valve", "hmi_washing_all"]
	for e in expected:
		_check(ids.has(e), "S1 spec present for '%s'" % e)
	var clips_ok := 0
	var clips_bad : Array = []
	var loops_ok := 0
	var loops_bad : Array = []
	var shots_ok := 0
	var shots_bad : Array = []
	for id in ids:
		var s = BankScript.spec_for(id)
		if s == null or not ("gain_db" in s):
			_check(false, "S1 %s.tres does not load as a MachineSoundSpec" % id)
			continue
		var loops : Array = [String(s.run_loop), String(s.idle_loop)]
		var shots : Array = [String(s.start_clip), String(s.stop_clip), String(s.alarm_clip)]
		for k in s.event_clips:
			shots.append(String(s.event_clips[k]))
		for p in loops + shots:
			if p == "":
				continue
			if not ResourceLoader.exists(p):
				clips_bad.append("%s: %s missing" % [id, p])
				continue
			var info := _wav_info(p)
			if not bool(info["ok"]):
				clips_bad.append("%s: %s %s" % [id, p, info])
				continue
			clips_ok += 1
			var is_loop : bool = loops.has(p)
			if is_loop:
				if int(info["loop"]) == AudioStreamWAV.LOOP_FORWARD:
					loops_ok += 1
				else:
					loops_bad.append("%s: %s loop_mode %d (importer did not read the smpl chunk)" % [id, p, int(info["loop"])])
			else:
				if int(info["loop"]) == AudioStreamWAV.LOOP_DISABLED:
					shots_ok += 1
				else:
					shots_bad.append("%s: %s loops (mode %d) but is a one-shot" % [id, p, int(info["loop"])])
	# 18 clips are baked; 16 are referenced: 10 loops (the compactor's 3x ring-line
	# sequence is a LOOP — operator 2026-09-25) and 6 one-shots. Two spares are
	# baked for the operator to swap in from the inspector: valve_crank_4, and the
	# second dryer window mech_dryer_run_30s ("I'll let you know what dryer is which").
	_check(clips_bad.is_empty() and clips_ok >= 16,
		"S1 every referenced WAV exists as 16-bit stereo 44.1 kHz PCM (%d ok) %s" % [clips_ok, clips_bad])
	_check(loops_bad.is_empty() and loops_ok >= 10,
		"S1 every loop imports as LOOP_FORWARD from its smpl chunk (%d) %s" % [loops_ok, loops_bad])
	_check(shots_bad.is_empty() and shots_ok >= 6,
		"S1 every one-shot imports without a loop (%d) %s" % [shots_ok, shots_bad])
	_check(ResourceLoader.exists("res://assets/audio/machines/valve_crank_4.wav"),
		"S1 the spare valve take (crank 4) is baked for the operator to swap in")
	_check(ResourceLoader.exists("res://assets/audio/machines/mech_dryer_run_30s.wav"),
		"S1 the second dryer window (30-42 s) is baked, awaiting the operator's L/R assignment")
	var tz = BankScript.spec_for("trilzeef")
	_check(tz != null and tz.gain_db > -40.0 and tz.gain_db < 12.0 and tz.notes.find("PLACEHOLDER") != -1,
		"S1 the trilzeef spec carries a gain_db slider value (%.1f dB) and says its levels are placeholders" % (tz.gain_db if tz else 0.0))

func _s2_attach() -> void:
	print("-- S2: attach contract")
	var m : Node3D = PlaceableCatalog.build_node("trilzeef", false)
	_check(m != null, "S2 catalog built a trilzeef")
	var snd = BankScript.find(m)
	_check(snd != null and snd.has_method("set_drive"), "S2 the trilzeef body carries a MachineSound child")
	_check(snd != null and bool(snd.call("has_run_loop")), "S2 …with the run loop loaded")
	var again = BankScript.attach(m, "trilzeef")
	_check(again == snd, "S2 attach() is idempotent (rebuild_in_place cannot stack two)")
	var ghost : Node3D = PlaceableCatalog.build_node("trilzeef", true)
	_check(ghost != null and BankScript.find(ghost) == null, "S2 a build-mode ghost gets no sound")
	var mute : Node3D = PlaceableCatalog.build_node("centrifuge", false)
	_check(mute != null and BankScript.find(mute) == null, "S2 a machine without a .tres (centrifuge) gets no sound — silence is data, not a default")
	for n in [m, ghost, mute]:
		if n != null:
			n.free()

func _s3_drive() -> void:
	print("-- S3: drive semantics on a real trilzeef")
	var m : Node3D = PlaceableCatalog.build_node("trilzeef", false)
	add_child(m)
	await get_tree().process_frame
	var snd = BankScript.find(m)
	var run : AudioStreamPlayer3D = snd.call("run_player")
	var spec = snd.get("spec")
	_check(not bool(snd.call("is_running")) and not run.playing, "S3 not operating → the loop player is not playing")
	# ramp up
	await _hold(snd, 1.0, 0.8)
	_check(bool(snd.call("is_running")) and run.playing, "S3 drive 1 → running, loop playing")
	var d : float = float(snd.call("drive"))
	_check(d > 0.97, "S3 drive follows the target within 0.8 s (%.3f)" % d)
	_check(absf(run.pitch_scale - 1.0) < 0.02, "S3 at full drive the pitch is 1.0 (%.3f)" % run.pitch_scale)
	_check(absf(run.volume_db - float(spec.gain_db)) < 0.3,
		"S3 at full drive the level is the spec's gain_db (%.1f vs %.1f dB)" % [run.volume_db, float(spec.gain_db)])
	_check(run.bus == "Machines", "S3 plays on the Machines bus (%s)" % run.bus)
	_check(absf(run.unit_size - float(spec.unit_size_m)) < 0.01 and absf(run.max_distance - float(spec.max_distance_m)) < 0.01,
		"S3 attenuation radii come from the spec (%.1f / %.1f m)" % [run.unit_size, run.max_distance])
	# half speed — a DECREASE, so the spec's ramp_down_s (trilzeef 3 s: 1/3 per
	# second) governs how fast the drive gets there: 1.5 s from 1.0 to 0.5.
	await _hold(snd, 0.5, float(spec.ramp_down_s) * 0.5 + 0.6)
	var want_pitch : float = lerpf(float(spec.pitch_floor), 1.0, 0.5)
	_check(absf(run.pitch_scale - want_pitch) < 0.03,
		"S3 at half drive the pitch sits between the floor and 1.0 (%.3f, want %.3f)" % [run.pitch_scale, want_pitch])
	_check(run.volume_db < float(spec.gain_db) - 1.0 and run.volume_db > float(spec.gain_db) + float(spec.ramp_db_floor) + 1.0,
		"S3 at half drive the level sits between the floor and gain (%.1f dB)" % run.volume_db)
	# ramp down honours the spec's ramp_down_s (trilzeef: 3 s) — slower than the target
	var t0 := Time.get_ticks_msec()
	var d_prev : float = float(snd.call("drive"))
	var monotonic := true
	var seen_mid := false
	while Time.get_ticks_msec() - t0 < 1000:
		snd.call("set_drive", 0.0)
		await get_tree().process_frame
		var dn : float = float(snd.call("drive"))
		if dn > d_prev + 1e-6:
			monotonic = false
		d_prev = dn
		if dn > 0.05 and dn < 0.45:
			seen_mid = true
	_check(monotonic and seen_mid and bool(snd.call("is_running")),
		"S3 ramp-down: after 1 s at target 0 the drive is still coasting (%.3f), monotonic, loop still playing" % d_prev)
	_check(run.pitch_scale < 0.9 and run.volume_db < float(spec.gain_db) - 3.0,
		"S3 …and it SOUNDS like a ramp-down: pitch %.3f, level %.1f dB" % [run.pitch_scale, run.volume_db])
	await _hold(snd, 0.0, float(spec.ramp_down_s) + 0.5)
	_check(not bool(snd.call("is_running")) and not run.playing and float(snd.call("drive")) == 0.0,
		"S3 after ramp_down_s the player is STOPPED (not merely quiet)")
	await _free_body(m)
	# driver watchdog on a spec with no coast (laser_filter: ramp_down_s 0)
	var lf3 : Node3D = PlaceableCatalog.build_node("laser_filter", false)
	add_child(lf3)
	await get_tree().process_frame
	var snd2 = BankScript.find(lf3)
	await _hold(snd2, 1.0, 0.6)
	_check(bool(snd2.call("is_running")), "S3 watchdog: laser filter running while driven")
	await _wait(1.8)   # nobody calls set_drive
	_check(not bool(snd2.call("is_running")) and float(snd2.call("target")) == 0.0,
		"S3 watchdog: 1.8 s without a driver → target 0, stopped (a machine that left the graph goes quiet)")
	await _free_body(lf3)

func _s4_lineflow() -> void:
	print("-- S4: LineFlow drives the sound from spin")
	var m : Node3D = PlaceableCatalog.build_node("trilzeef", false)
	m.add_to_group("placed_object")
	add_child(m)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var i := _node_index_by_id(nodes, "trilzeef")
	_check(i >= 0, "S4 LineFlow discovered the trilzeef (%d nodes)" % nodes.size())
	if i < 0:
		lf.free(); await _free_body(m); return
	var nd : Dictionary = nodes[i]
	var snd = nd.get("snd")
	_check(snd != null and snd == BankScript.find(m), "S4 the node dict holds the machine's MachineSound")
	var key := String(nd.get("key", ""))
	lf.call("set_machine_hand_mode", key, true)
	lf.call("set_machine_manual_on", key, true)
	var ramp : Array = []
	for _t in 30:
		lf.call("tick", TICK_S)
		ramp.append(float(snd.call("target")))
	var rising := true
	for k in range(1, 10):
		if ramp[k] < ramp[k - 1] - 1e-6:
			rising = false
	_check(rising and ramp[0] < 0.2 and ramp[29] > 0.99,
		"S4 hand ON: the sound target ramps with spin over SPIN_UP_S (t=0.1 s %.2f, t=1.0 s %.2f, t=3.0 s %.2f)" % [ramp[0], ramp[9], ramp[29]])
	await _wait(0.5)
	_check(bool(snd.call("is_running")) and float(snd.call("drive")) > 0.95,
		"S4 …and the component followed it to full (drive %.2f, running)" % float(snd.call("drive")))
	lf.call("set_machine_manual_on", key, false)
	var down : Array = []
	for _t in 30:
		lf.call("tick", TICK_S)
		down.append(float(snd.call("target")))
	_check(down[29] == 0.0 and down[9] > 0.4 and down[9] < 0.8,
		"S4 hand OFF: target falls with spin (t=1.0 s %.2f, t=3.0 s %.2f)" % [down[9], down[29]])
	lf.free()
	await _free_body(m)

func _s5_leafblower() -> void:
	print("-- S5: leaf blower start / idle / rev / stop")
	var lb : Node3D = PlaceableCatalog.build_node("tool_leafblower", false)
	add_child(lb)
	await get_tree().process_frame
	var snd = BankScript.find(lb)
	_check(snd != null, "S5 the leaf blower carries its MachineSound")
	if snd == null:
		await _free_body(lb); return
	var idle : AudioStreamPlayer3D = snd.call("idle_player")
	var rev  : AudioStreamPlayer3D = snd.call("run_player")
	var fx   : AudioStreamPlayer3D = snd.call("fx_player")
	_check(idle != null and rev != null and idle.stream != null and rev.stream != null,
		"S5 idle and rev loops loaded")
	_check(float(lb.call("sound_drive")) == 0.0 and not idle.playing, "S5 OFF: drive 0, nothing playing")
	# The blower is not held, so its own _physics_process would reset it to OFF
	# every physics frame. Freeze the state machine and drive the mapping by hand:
	# what is under test is sound_drive() → MachineSound, not the trigger input.
	lb.set_physics_process(false)
	# pull the starter: OFF → SPOOLING_UP with a little spool
	lb.set("_state", 1)        # State.SPOOLING_UP
	lb.set("_spool", 0.05)
	lb.call("_update_sound")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(fx.playing, "S5 the start clip plays on the OFF→SPOOLING_UP edge")
	_check(idle.playing and rev.playing, "S5 both loops run (crossfaded by spool)")
	await _wait(0.3)
	lb.call("_update_sound")
	await get_tree().process_frame
	_check(idle.volume_db > rev.volume_db + 10.0,
		"S5 at spool 0.05 the IDLE dominates (idle %.1f dB, rev %.1f dB)" % [idle.volume_db, rev.volume_db])
	lb.set("_state", 2)        # FULL_THROTTLE
	lb.set("_spool", 1.0)
	for _f in 40:
		lb.call("_update_sound")
		await get_tree().process_frame
	_check(rev.volume_db > idle.volume_db + 10.0,
		"S5 at full spool the REV loop dominates (rev %.1f dB, idle %.1f dB)" % [rev.volume_db, idle.volume_db])
	_check(idle.pitch_scale > 1.2, "S5 …and the idle is pitched up under it (%.2f)" % idle.pitch_scale)
	lb.set("_state", 0)        # OFF
	lb.set("_spool", 0.0)
	lb.call("_update_sound")
	await get_tree().process_frame
	await get_tree().process_frame
	_check(fx.playing, "S5 …the stop clip (engine dying) starts the moment the model says OFF")
	# The loops follow the drive down with the component's 0.12 s time constant
	# (the spec has no ramp_down_s): ~0.6 s under the 2.8 s stop clip, then STOP.
	await _wait(0.8)
	_check(not idle.playing and not rev.playing, "S5 OFF: both loops stopped within 0.8 s")
	_check(fx.playing, "S5 …while the stop clip is still playing over them")
	await _free_body(lb)

func _s6_valves() -> void:
	print("-- S6: the valve crank")
	var reel : Node3D = PlaceableCatalog.build_node("reel_water_black", false)
	add_child(reel)
	await get_tree().process_frame
	var ctrl := reel.find_child("HoseReelController", true, false)
	_check(ctrl != null, "S6 the hose reel has its controller")
	if ctrl != null:
		ctrl.call("_cycle_base_valve")          # DICHT → WEINIG
		var snd = BankScript.find(reel)
		_check(snd != null, "S6 the first turn attaches hose_reel_valve to the reel body")
		if snd != null:
			var ev : AudioStreamPlayer3D = snd.call("event_player")
			_check(ev.playing and int(snd.call("events_played").get("valve_open", 0)) == 1,
				"S6 DICHT→WEINIG plays valve_open (%s)" % [snd.call("events_played")])
			ctrl.call("_cycle_base_valve")      # WEINIG → OPEN
			ctrl.call("_cycle_base_valve")      # OPEN → DICHT
			var played : Dictionary = snd.call("events_played")
			_check(int(played.get("valve_open", 0)) == 2 and int(played.get("valve_close", 0)) == 1,
				"S6 a full cycle is open, open, close (%s)" % [played])
	await _free_body(reel)
	var ibc : Node3D = PlaceableCatalog.build_node("ibc_tote", false)
	add_child(ibc)
	await get_tree().process_frame
	_check(ibc != null and ibc.has_method("open_valve_sound"), "S6 the IBC tote is a WasteContainer with a valve sound hook")
	if ibc != null and ibc.has_method("open_valve_sound"):
		var ok : bool = bool(ibc.call("open_valve_sound"))
		var snd2 = BankScript.find(ibc)
		_check(ok and snd2 != null and int(snd2.call("events_played").get("valve_open", 0)) == 1,
			"S6 opening the IBC drain plays its crank take")
	await _free_body(ibc)

func _s7_compactor() -> void:
	print("-- S7: compactor — the 3x ring-line sequence LOOPS while it runs")
	var c : Node3D = PlaceableCatalog.build_node("compactor", false)
	add_child(c)
	await get_tree().process_frame
	var snd = BankScript.find(c)
	_check(snd != null, "S7 the compactor carries its MachineSound")
	if snd == null:
		await _free_body(c); return
	var spec = snd.get("spec")
	_check(String(spec.run_loop).ends_with("compactor_ringleiding_loop.wav") and String(spec.periodic_event) == "",
		"S7 spec: the 1:11-1:14 window x3 is the RUN LOOP (operator: 'that entire sound of the three, in a sequence, has to loop'), not a periodic event (%s)" % spec.run_loop)
	var run : AudioStreamPlayer3D = snd.call("run_player")
	var has_wav : bool = run != null and run.stream != null and run.stream is AudioStreamWAV
	_check(has_wav and (run.stream as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"S7 the loop imports as LOOP_FORWARD from its smpl chunk")
	var len_s : float = run.stream.get_length() if has_wav else 0.0
	_check(len_s > 8.85 and len_s < 8.97,
		"S7 its length is 3 x 3.0 s minus three 30 ms joins = 8.91 s (%.3f s)" % len_s)
	_check(has_wav and not run.playing, "S7 compactor off → silent")
	await _hold(snd, 1.0, 0.8)
	_check(bool(snd.call("is_running")) and has_wav and run.playing and absf(run.pitch_scale - 1.0) < 0.01,
		"S7 running → the sequence loops at pitch 1.0 (%.3f)" % (run.pitch_scale if has_wav else 0.0))
	await _hold(snd, 0.5, 0.8)
	_check(has_wav and absf(run.pitch_scale - 1.0) < 0.01,
		"S7 at half drive the pitch STAYS 1.0 — air pulses do not pitch-bend with motor speed (pitch_floor 1.0) (%.3f)" % (run.pitch_scale if has_wav else 0.0))
	await _hold(snd, 0.0, 0.8)
	_check(not bool(snd.call("is_running")) and has_wav and not run.playing,
		"S7 off again → the loop is STOPPED, not merely quiet")
	await _free_body(c)

func _s8_wash_alarm() -> void:
	print("-- S8: the wash-line panel's alarm beep")
	var panel : Node3D = PlaceableCatalog.build_node("hmi_washing_all", false)
	add_child(panel)
	await get_tree().process_frame
	var snd = BankScript.find(panel)
	_check(snd != null and snd.call("alarm_player") != null, "S8 the waslijn panel carries the alarm beep")
	if snd == null:
		await _free_body(panel); return
	var ap : AudioStreamPlayer3D = snd.call("alarm_player")
	_check(not bool(snd.call("alarm_active")), "S8 no fault → silent")
	EventBus.machine_alarm_raised.emit("friction_washer", "OVERLOAD-ESTOP", 3)
	await _wait(0.4)
	_check(bool(snd.call("alarm_active")) and ap.playing,
		"S8 OVERLOAD-ESTOP on a friction washer → the panel beeps (period %.1f s)" % float(snd.get("spec").alarm_period_s))
	panel.call("acknowledge_alarms")
	await _wait(0.4)
	_check(not bool(snd.call("alarm_active")), "S8 KWITTEREN → silent while the fault stands")
	EventBus.machine_alarm_raised.emit("friction_washer", "OVERLOAD-ESTOP", 3)
	await _wait(0.4)
	_check(not bool(snd.call("alarm_active")), "S8 the same live alarm re-emitted is not a new occurrence")
	EventBus.machine_alarm_cleared.emit("friction_washer", "OVERLOAD-ESTOP")
	EventBus.machine_alarm_raised.emit("friction_washer", "OVERLOAD-ESTOP", 3)
	await _wait(0.4)
	_check(bool(snd.call("alarm_active")), "S8 cleared and tripped again → a NEW occurrence beeps again")
	EventBus.machine_alarm_cleared.emit("friction_washer", "OVERLOAD-ESTOP")
	await _wait(0.4)
	_check(not bool(snd.call("alarm_active")), "S8 the fault clearing silences it")
	EventBus.machine_alarm_raised.emit("extruder_3a", "fault", 3)
	await _wait(0.4)
	_check(not bool(snd.call("alarm_active")), "S8 an extruder fault is not this panel's business")
	EventBus.machine_alarm_cleared.emit("extruder_3a", "fault")
	# The overlay's scoped faults count too, and its KWITTEREN silences the panel.
	var ov = (load(OVERLAY_SCENE) as PackedScene).instantiate()
	add_child(ov)
	await get_tree().process_frame
	ov.set("_last_faults", [{"code": "BUF-300", "text": "test", "scope": "friction_washer"},
		{"code": "INV-101", "text": "global", "scope": ""}])
	# The panel's REAL tokens (HmiScopes), the same substring rule the overlay's
	# section lamps use, so the beep and the lamp always agree.
	var wash_tokens : Array = HmiScopes.get_scope("hmi_washing_all").get("tokens", [])
	var extr_tokens : Array = HmiScopes.get_scope("hmi_extruder_all").get("tokens", [])
	_check(int(ov.call("unacked_count_for_tokens", wash_tokens)) == 1
		and int(ov.call("unacked_count_for_tokens", extr_tokens)) == 0,
		"S8 overlay: a BUF-300 at a friction_washer counts for the wash panel's tokens only (wash %d, extruder %d); a global INV-101 for nobody"
		% [int(ov.call("unacked_count_for_tokens", wash_tokens)), int(ov.call("unacked_count_for_tokens", extr_tokens))])
	HmiScript._overlay = ov
	await _wait(0.4)
	_check(bool(snd.call("alarm_active")), "S8 the panel beeps on the overlay's scoped, unacknowledged fault")
	ov.call("_on_kwitteren")
	await _wait(0.4)
	_check(not bool(snd.call("alarm_active")), "S8 KWITTEREN on the overlay silences the panel (faults_acknowledged)")
	HmiScript._overlay = null
	ov.free()
	await _free_body(panel)

func _finish() -> void:
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
