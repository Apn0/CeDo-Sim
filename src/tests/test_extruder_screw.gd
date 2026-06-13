extends Node
## Headless verification of the non-Newtonian extruder screw physics (#45).
##
## Pure-sim module (RefCounted, no autoloads), so this runs either way:
##   godot --headless --path . --script res://src/tests/test_extruder_screw.gd
##   godot --headless --path . res://src/tests/test_extruder_screw.tscn
##
## Asserts the spec's three headline behaviours:
##   1. rpm↑  →  viscosity↓  AND  shear_heat↑   (shear-thinning + viscous dissipation)
##   2. melt_temp can EXCEED the barrel setpoint purely on friction (adiabatic)
##   3. the cooling fan pulls a runaway melt BACK into the 190–200 °C window
##
## Follows the test_settings_wiring.gd pattern: _ok/_section helpers, a pass/fail
## summary, and get_tree().quit() with a non-zero code on failure.

const ExtruderScrewScript = preload("res://src/sim/ExtruderScrew.gd")

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

## Drive an extruder with a FIXED 0.1 s tick (the SimTick cadence) for `secs`
## seconds — deterministic regardless of how the headless engine paces frames.
func _run(ex, secs: float) -> void:
	var steps := int(round(secs / 0.1))
	for _i in steps:
		ex.tick(0.1)

func _ready() -> void:
	print("=== Extruder screw physics verification (#45) ===")

	# Build at the 195 °C barrel setpoint, started warm (already at setpoint) so the
	# tests isolate SHEAR behaviour rather than a cold-start transient.
	var barrel := 195.0

	# ── 1. Shear-thinning + viscous dissipation: rpm↑ → viscosity↓, shear_heat↑ ──
	_section("shear-thinning (rpm vs viscosity & shear heat)")
	# LOW rpm steady state, fan OFF so temperature settles on physics alone.
	var lo = ExtruderScrewScript.new(barrel, barrel)
	lo.set_fan_manual(0.0)
	lo.set_rpm(40.0)
	_run(lo, 60.0)
	# HIGH rpm steady state, same conditions.
	var hi = ExtruderScrewScript.new(barrel, barrel)
	hi.set_fan_manual(0.0)
	hi.set_rpm(140.0)
	_run(hi, 60.0)

	print("    lo(40rpm):  eta=%.0f Pa·s  shear=%.3f °C/s  melt=%.1f°C" % [lo.viscosity, lo.shear_heat, lo.melt_temp])
	print("    hi(140rpm): eta=%.0f Pa·s  shear=%.3f °C/s  melt=%.1f°C" % [hi.viscosity, hi.shear_heat, hi.melt_temp])

	_ok(hi.screw_rpm > lo.screw_rpm, "higher rpm command reached (%.0f > %.0f)" % [hi.screw_rpm, lo.screw_rpm])
	_ok(hi.viscosity < lo.viscosity,
		"rpm↑ ⇒ viscosity↓ (shear-thinning): %.0f Pa·s < %.0f Pa·s" % [hi.viscosity, lo.viscosity])
	_ok(hi.shear_heat > lo.shear_heat,
		"rpm↑ ⇒ shear_heat↑ (viscous dissipation): %.3f > %.3f °C/s" % [hi.shear_heat, lo.shear_heat])
	# The heat law itself is STEEP (super-linear in rpm): heat = K·gamma^(n+1),
	# n+1≈1.35. Compare at a MATCHED melt temperature so Arrhenius thinning (which
	# differs between the two divergent steady states above) can't muddy the law —
	# pin both melts equal, re-tick once, and read the dissipation at that instant.
	lo.melt_temp = 195.0
	hi.melt_temp = 195.0
	lo.tick(0.1)
	hi.tick(0.1)
	var rpm_ratio : float = hi.screw_rpm / maxf(lo.screw_rpm, 0.01)
	var heat_ratio : float = hi.shear_heat / maxf(lo.shear_heat, 1e-6)
	print("    at matched 195°C: heat ×%.2f for rpm ×%.2f" % [heat_ratio, rpm_ratio])
	_ok(heat_ratio > rpm_ratio,
		"shear_heat climbs super-linearly with rpm (heat ×%.2f vs rpm ×%.2f)" % [heat_ratio, rpm_ratio])
	# A stopped screw generates no shear heat at all.
	var off = ExtruderScrewScript.new(barrel, barrel)
	off.set_fan_manual(0.0)
	off.set_rpm(0.0)
	_run(off, 5.0)
	_ok(off.shear_heat == 0.0, "stopped screw ⇒ zero shear heat (%.3f)" % off.shear_heat)

	# ── 2. Adiabatic: melt_temp can EXCEED the barrel setpoint on friction alone ──
	_section("adiabatic melt overshoot (no fan)")
	var hot = ExtruderScrewScript.new(barrel, barrel)
	hot.set_fan_manual(0.0)          # fans OFF — nothing to brake the self-heating
	hot.set_rpm(150.0)
	_run(hot, 90.0)
	print("    150rpm, fan off: melt=%.1f°C  barrel=%.0f°C  superheat=+%.1f°C" % [hot.melt_temp, hot.barrel_temp, hot.superheat_over_barrel()])
	_ok(hot.melt_temp > hot.barrel_temp,
		"melt_temp exceeds barrel setpoint via friction: %.1f°C > %.0f°C" % [hot.melt_temp, hot.barrel_temp])
	_ok(hot.superheat_over_barrel() > 0.0,
		"superheat_over_barrel() reports +%.1f °C" % hot.superheat_over_barrel())

	# ── 3. Cooling fan pulls a runaway melt back into 190–200 °C ─────────────────
	_section("cooling fan holds the 190–200 °C target")
	var ctl = ExtruderScrewScript.new(barrel, barrel)
	ctl.set_fan_auto()               # PI fan controller engaged
	ctl.set_rpm(150.0)               # same hard-driving rpm that overshot above
	# Let it run to steady state (rpm ramp + thermal settle + controller convergence).
	_run(ctl, 180.0)
	print("    150rpm, fan AUTO: melt=%.1f°C  fan=%.0f%%  (target 190–200°C)" % [ctl.melt_temp, ctl.cooling_fan_level * 100.0])
	_ok(ctl.cooling_fan_level > 0.0,
		"fan ramped up to fight the heat (%.0f%%)" % (ctl.cooling_fan_level * 100.0))
	_ok(ctl.melt_in_target_band(),
		"fan held melt in 190–200 °C window (%.1f°C)" % ctl.melt_temp)
	# And it's strictly cooler than the identical un-fanned run — the fan did work.
	_ok(ctl.melt_temp < hot.melt_temp,
		"fanned melt is cooler than the un-fanned run (%.1f°C < %.1f°C)" % [ctl.melt_temp, hot.melt_temp])

	# ── 4. die_pressure surface is live (so the MFI-proxy task can read it) ──────
	_section("die pressure exposed for the MFI proxy")
	_ok(ctl.die_pressure > 0.0, "die_pressure is published (%.2f bar)" % ctl.die_pressure)
	# Thinner (hotter/faster-sheared) melt ⇒ lower head pressure at equal throughput.
	var thick = ExtruderScrewScript.new(barrel, barrel)
	thick.set_fan_manual(0.0)
	thick.set_rpm(40.0)
	thick.set_throughput(0.5)
	_run(thick, 60.0)
	var thin = ExtruderScrewScript.new(barrel, barrel)
	thin.set_fan_manual(0.0)
	thin.set_rpm(140.0)
	thin.set_throughput(0.5)
	_run(thin, 60.0)
	_ok(thin.die_pressure < thick.die_pressure,
		"thinner melt ⇒ lower die pressure at equal flow (%.2f < %.2f bar)" % [thin.die_pressure, thick.die_pressure])

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	# Quit with a non-zero code on failure so CI / run_tests.bat can gate on it.
	if is_inside_tree():
		get_tree().quit(0 if _fail == 0 else 1)
