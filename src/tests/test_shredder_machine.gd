extends Node
# #227 — proves the Shredder sim (ShredderMachine.gd) is functional + REPEATABLE:
# output tracks feed + caps at rated, motor load, overfeed backs up, sustained
# overload TRIPS + resets, e-stop interlock, Onderhoud-key interlock, twin rotors
# found for spin-gating. Scene-based (autoload-safe). Run:
#   godot --headless --path . res://src/tests/test_shredder_machine.tscn
var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] shredder machine")
	var sh : Node = PlaceableCatalog.build_node("shredder_1", false)
	add_child(sh)
	await get_tree().process_frame
	_check(sh.has_method("set_feed_throughput"), "S0 shredder_1 carries the ShredderMachine brain")
	_check(int(sh.get("rated_kg_h")) == 4500, "S0 coarse rated 4500 kg/h (%s)" % str(sh.get("rated_kg_h")))

	# ── S1 normal run: output tracks feed, load ≈ feed/rated, rotors gated ────
	sh.set_feed_throughput(3000.0)
	sh.call("start")
	for _i in 80: sh._physics_process(0.1)
	_check(sh.call("is_running"), "S1 running after start")
	_check(absf(float(sh.get("throughput_kg_h")) - 3000.0) < 250.0, "S1 output tracks feed (%.0f kg/h)" % float(sh.get("throughput_kg_h")))
	_check(absf(float(sh.get("motor_load_pct")) - 66.7) < 10.0, "S1 motor load ≈ feed/rated (%.0f%%)" % float(sh.get("motor_load_pct")))
	_check((sh.get("_rotors") as Array).size() >= 2, "S1 TWIN rotors found for spin-gating (%d)" % (sh.get("_rotors") as Array).size())

	# ── S1b throughput tracks rotor spin-up, not just the run flag (#C3) ─────
	# A fresh machine started this tick should still be near-stopped: rotor rpm
	# has real inertia (RotatingMechanism.spin_up_s), so output must ramp in,
	# not snap to full rate the instant `running` flips true.
	var sh2 : Node = PlaceableCatalog.build_node("shredder_1", false)
	add_child(sh2)
	await get_tree().process_frame
	sh2.set_feed_throughput(3000.0)
	sh2.call("start")
	sh2._physics_process(0.05)   # one tick, 50ms after start
	_check(float(sh2.get("throughput_kg_h")) < 900.0, "S1b throughput still near-zero 50ms after start (%.0f kg/h)" % float(sh2.get("throughput_kg_h")))
	var spin_up_s : float = float((sh2.get("_rotors") as Array)[0].get("spin_up_s"))
	for _i in int(spin_up_s / 0.1) + 20: sh2._physics_process(0.1)
	_check(float(sh2.get("throughput_kg_h")) > 2500.0, "S1b throughput reaches feed rate once spun up (%.0f kg/h, spin_up_s=%.1f)" % [float(sh2.get("throughput_kg_h")), spin_up_s])
	sh2.queue_free()

	# ── S2 overfeed: output caps at rated, buffer backs up ───────────────────
	sh.set_feed_throughput(6000.0)
	var buf0 : float = float(sh.get("buffer_kg"))
	for _i in 20: sh._physics_process(0.1)
	_check(float(sh.get("throughput_kg_h")) <= 4500.0 * 1.03, "S2 output capped at rated (%.0f)" % float(sh.get("throughput_kg_h")))
	_check(float(sh.get("buffer_kg")) > buf0, "S2 overfeed backs up in the buffer")

	# ── S3 sustained overload TRIPS the motor ────────────────────────────────
	for _i in 90: sh._physics_process(0.1)   # ~9 s sustained overfeed
	_check(bool(sh.get("is_tripped")), "S3 sustained overload trips the motor protection")
	_check(not sh.call("is_running"), "S3 tripped → stopped")

	# ── S4 reset + restart = repeatable ──────────────────────────────────────
	sh.call("reset_trip")
	sh.set_feed_throughput(2000.0)
	sh.call("start")
	for _i in 30: sh._physics_process(0.1)
	_check(sh.call("is_running") and float(sh.get("throughput_kg_h")) > 1500.0, "S4 reset + restart runs again (repeatable)")

	# ── S5 e-stop interlock ──────────────────────────────────────────────────
	sh.call("emergency_stop")
	_check(not sh.call("is_running"), "S5 e-stop stops it")
	sh.call("start")
	_check(not sh.call("is_running"), "S5 NEGATIVE: cannot start while e-stopped")
	sh.call("release_estop")
	sh.call("start")
	for _i in 10: sh._physics_process(0.1)
	_check(sh.call("is_running"), "S5 release e-stop → starts")

	# ── S6 Onderhoud key interlock ───────────────────────────────────────────
	sh.call("set_key_position", 2)   # ONDERHOUD
	_check(not sh.call("is_running"), "S6 Onderhoud detent forces a stop")
	sh.call("start")
	_check(not sh.call("is_running"), "S6 NEGATIVE: cannot start in Onderhoud")

	if _fails == 0:
		print("[TEST] shredder machine PASS")
	else:
		print("[TEST] shredder machine FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
