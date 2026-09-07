extends SceneTree
## Headless, deterministic verification of MotorOverload.gd (the "pack-up" cascade:
## paddle load → amp spike → sustained-overload TRIP).
##
## Self-contained: MotorOverload is a plain RefCounted, so this needs NO autoloads
## and NO scene. It runs straight off the script entry point:
##
##   godot --headless --script res://src/tests/test_motor_overload.gd
##
## Reporting follows the repo-root test_settings_wiring.gd pattern (_ok / pass /
## fail counters + a summary), but as a SceneTree script it can boot without a
## .tscn. Every tick uses a FIXED delta so the result is fully deterministic and
## independent of engine frame pacing.

const MotorOverloadScript = preload("res://src/sim/MotorOverload.gd")

const DT := 0.1   # fixed sim step (s)

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

## Advance a motor by `seconds` of sim time in fixed DT steps.
func _run_for(motor, seconds: float) -> void:
	var steps := int(round(seconds / DT))
	for _i in steps:
		motor.tick(DT)

func _init() -> void:
	print("=== MotorOverload verification ===")

	# A drive with clear, well-separated tunables so the thresholds are unambiguous.
	#   nominal 90 A · locked-rotor 480 A · trip > 180 A held 3.0 s · binds at 120 kg
	var make := func():
		return MotorOverloadScript.new("shredder_test", 90.0, 480.0, 180.0, 3.0, 120.0)

	# ── 1. Amps RISE monotonically with accumulated_kg ─────────────────────────
	_section("amps rise with accumulated_kg")
	var m = make.call()
	m.tick(DT)
	var a_empty : float = m.current_amps
	# Empty + spinning → idle floor (35% of nominal = 31.5 A), well under nominal.
	_ok(abs(a_empty - 90.0 * 0.35) < 0.001,
		"empty motor idles at %.1f A (35%% of nominal)" % a_empty)

	m.add_load(60.0)          # half the binding load → ~midway idle→nominal
	m.tick(DT)
	var a_half : float = m.current_amps
	_ok(a_half > a_empty, "60 kg load (%.1f A) draws more than empty (%.1f A)" % [a_half, a_empty])

	m.add_load(60.0)          # now 120 kg = binding point → exactly nominal
	m.tick(DT)
	var a_full : float = m.current_amps
	_ok(a_full > a_half, "120 kg load (%.1f A) draws more than 60 kg (%.1f A)" % [a_full, a_half])
	_ok(abs(a_full - 90.0) < 0.001, "at the binding load (120 kg) amps == nominal (%.1f A)" % a_full)

	m.add_load(120.0)         # 240 kg = 2× binding → fully stalled → locked-rotor
	m.tick(DT)
	var a_stall : float = m.current_amps
	_ok(a_stall > a_full, "240 kg load (%.1f A) draws more than the binding load (%.1f A)" % [a_stall, a_full])
	_ok(abs(a_stall - 480.0) < 0.001, "at 2x binding load amps saturate at locked-rotor (%.1f A)" % a_stall)
	_ok(not m.is_tripped(), "a single overloaded tick has NOT tripped yet (needs sustained time)")

	# ── 2. A brief spike under trip_delay must NOT trip ────────────────────────
	_section("brief spike does not trip")
	var m2 = make.call()
	m2.add_load(300.0)                 # heavy overload → amps way over threshold
	m2.tick(DT)
	_ok(m2.current_amps > m2.trip_threshold,
		"overloaded draw %.0f A is over the %.0f A trip threshold" % [m2.current_amps, m2.trip_threshold])
	_run_for(m2, 2.0)                  # hold 2.0 s — LESS than the 3.0 s trip_delay
	_ok(not m2.is_tripped(), "held 2.0 s (< 3.0 s trip_delay) → still running, no trip")
	# Relieve below threshold, then re-load: the overload clock must have RESET,
	# so a fresh sustained overload starts counting from zero (not from 2.0 s).
	m2.relieve(300.0)
	m2.tick(DT)
	_ok(m2.current_amps <= m2.trip_threshold, "after relieving, draw is back under threshold")
	_ok(m2.time_to_trip() < 0.0, "no trip pending once under threshold (time_to_trip < 0)")

	# ── 3. A SUSTAINED overload trips after trip_delay ─────────────────────────
	_section("sustained overload trips after trip_delay")
	var m3 = make.call()
	var trip_events : Array = []
	m3.tripped.connect(func(id, amps): trip_events.append({"id": id, "amps": amps}))
	m3.add_load(300.0)                 # solid stall-level overload
	# Just BEFORE the delay elapses it must still be holding (not tripped).
	_run_for(m3, 2.9)
	_ok(not m3.is_tripped(), "at 2.9 s held → not yet tripped (just under 3.0 s)")
	_ok(m3.time_to_trip() > 0.0 and m3.time_to_trip() < 0.2,
		"time_to_trip counts down to ~0.1 s before the trip (%.2f s)" % m3.time_to_trip())
	# Cross the threshold time → trip.
	_run_for(m3, 0.3)                  # total ~3.2 s of sustained overload
	_ok(m3.is_tripped(), "after 3.0 s of sustained overload → TRIPPED")
	_ok(m3.current_amps == 0.0, "a tripped motor draws 0 A (stopped)")
	_ok(not m3.running, "a tripped motor is no longer running")
	_ok(trip_events.size() == 1, "the `tripped` signal fired exactly once")
	if trip_events.size() == 1:
		_ok(String(trip_events[0]["id"]) == "shredder_test",
			"trip signal carried the machine_id ('%s')" % String(trip_events[0]["id"]))
		_ok(float(trip_events[0]["amps"]) > m3.trip_threshold,
			"trip signal reported the peak draw %.0f A (over threshold)" % float(trip_events[0]["amps"]))
	# Latched: keep ticking the overload — it must NOT emit a second trip.
	_run_for(m3, 5.0)
	_ok(trip_events.size() == 1, "trip stays latched — no repeat `tripped` while still overloaded")
	_ok(m3.is_tripped(), "still tripped after more ticks (latched until reset)")

	# ── 4. Relieving load + reset() clears the trip ────────────────────────────
	_section("relieve + reset clears the trip")
	var reset_events : Array = []
	m3.reset_done.connect(func(id): reset_events.append(id))
	# Crew digs out the pack-up first, THEN the relay is reset.
	m3.relieve(1000.0)                 # over-relieve → load floors at 0
	_ok(m3.accumulated_kg == 0.0, "relieving more than present floors accumulated_kg at 0 kg")
	m3.reset()
	_ok(not m3.is_tripped(), "reset() clears the trip latch")
	_ok(m3.running, "reset() re-energises the motor (running == true)")
	_ok(reset_events.size() == 1, "the `reset_done` signal fired once on reset")
	m3.tick(DT)
	_ok(abs(m3.current_amps - 90.0 * 0.35) < 0.001,
		"after reset with no load, motor returns to idle draw (%.1f A)" % m3.current_amps)

	# ── 5. reset(clear_load=true) also empties the rotor ───────────────────────
	_section("reset(clear_load=true) empties the rotor")
	var m4 = make.call()
	m4.add_load(300.0)
	_run_for(m4, 3.5)                  # trip it
	_ok(m4.is_tripped() and m4.accumulated_kg > 0.0,
		"tripped with %.0f kg still piled on the rotor" % m4.accumulated_kg)
	m4.reset(true)                     # reset AND clear the jam in one call
	_ok(not m4.is_tripped(), "reset(true) clears the trip")
	_ok(m4.accumulated_kg == 0.0, "reset(true) also empties accumulated_kg")
	m4.tick(DT)
	_ok(m4.current_amps < m4.trip_threshold, "cleared motor runs normally (under threshold) after reset(true)")

	# ── 6. set_load() — the 2026-08-29 historical defect this method exists to fix ───────────
	# LineFlow.gd used to call add_load(_backlog_kg) EVERY TICK, where
	# _backlog_kg is a STOCK (the buffer's current level), not a one-off inflow
	# event — so the same standing kg got re-counted as fresh load forever.
	# Measured on line 1's real 'mill' node: buffer stayed under 7 kg the whole
	# run (genuinely keeping up), current_amps still raced to the 450 A
	# locked-rotor cap in ~10 s. set_load() mirrors the stock directly instead.
	_section("set_load() mirrors a stock — no false trip at a small STEADY level")
	var m5 = make.call()   # same 90A/480A/180A-3s/120kg rig as the others
	# Call set_load EVERY tick with the SAME small value, exactly like
	# LineFlow's per-tick call pattern — this is what falsely tripped before.
	for _i5 in 200:            # 20 s of sim time — 6.7x the 3.0 s trip_delay
		m5.set_load(6.5)       # matches the measured real-world mill buffer
		m5.tick(DT)
	_ok(not m5.is_tripped(),
		"20 s of a steady 6.5 kg buffer (well under 120 kg capacity) → no trip")
	_ok(m5.accumulated_kg == 6.5,
		"accumulated_kg mirrors the last set_load() call, not a running sum (%.1f kg)" % m5.accumulated_kg)

	_section("set_load() still catches a REAL sustained overload")
	var m6 = make.call()
	var m6_trips : Array = []   # array, not a bool: a lambda reassigning a
	                            # captured primitive does not propagate out in
	                            # GDScript, but mutating a captured container does
	m6.tripped.connect(func(_id, _amps): m6_trips.append(true))
	# A genuinely large, persistent buffer — the node truly cannot keep up,
	# same value held every tick (this IS what a real, growing pack-up looks
	# like from the caller's side: _backlog_kg stays pinned near its ceiling
	# because inflow keeps outrunning the machine's own processing rate).
	for _i6 in 50:              # 5 s — past the 3.0 s trip_delay
		m6.set_load(300.0)      # 2.5x the 120 kg binding capacity
		m6.tick(DT)
	_ok(m6.is_tripped(), "a genuinely-full 300 kg buffer, held sustained, still trips after trip_delay")
	_ok(m6_trips.size() == 1, "the `tripped` signal still fires for a genuine overload")

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)
