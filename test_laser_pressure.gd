extends SceneTree
## Proof for "laser filter under pressure with everything reading ZERO" (operator
## 2026-07-16 physics violation). An UNFED filter must hold ΔP at 0 (no pressure
## from nothing); a FED one must build pressure. Run:
##   Godot_v4.6.3_console --headless --path <proj> --script res://test_laser_pressure.gd

var _ran := false
var _idle : Node
var _fed : Node
var _f := 0

func _physics_process(_d: float) -> bool:
	if not _ran:
		_ran = true
		var scr = load("res://src/sim/LaserFilter.gd")
		_idle = scr.new(); get_root().add_child(_idle)
		_fed = scr.new(); get_root().add_child(_fed)
		_idle.feed_throughput_kg_h = 0.0      # nothing flowing
		_fed.feed_throughput_kg_h = 300.0     # real melt
		return false
	_f += 1
	if _f < 90:
		return false
	var idle_dp : float = _idle.delta_p_front_psi
	var idle_load : float = _idle.m1_load_pct
	var fed_dp : float = _fed.delta_p_front_psi
	var fails := 0
	print("  UNFED filter: ΔP=%.2f psi, M1-load=%.1f%%" % [idle_dp, idle_load])
	print("  FED   filter: ΔP=%.2f psi" % fed_dp)
	if idle_dp <= 0.001 and idle_load <= 0.001:
		print("  OK  : unfed filter holds ΔP + load at 0 — no pressure from nothing")
	else:
		print("  FAIL: unfed filter built ΔP %.2f / load %.1f from zero flow" % [idle_dp, idle_load]); fails += 1
	if fed_dp > 0.001:
		print("  OK  : fed filter builds real pressure (%.2f psi)" % fed_dp)
	else:
		print("  FAIL: fed filter shows no pressure under flow"); fails += 1
	print("=== LASER PRESSURE TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
