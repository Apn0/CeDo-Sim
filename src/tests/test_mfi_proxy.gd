extends SceneTree
## Headless test for MfiProxy (task #46) — the predictive MFI / die-pressure proxy.
##
## MfiProxy is a pure RefCounted sim class with no scene-tree / autoload deps, so
## this follows the repo's pure-logic test convention (test_conservation.gd):
## an `extends SceneTree` script driven directly, reporting ok/FAIL and a non-zero
## exit code on any failure (same pass/fail style as test_settings_wiring.gd).
##
## Run:  godot --headless --script res://src/tests/test_mfi_proxy.gd
##
## Asserts the headline property — predicted_mfi RISES when die_pressure FALLS at
## constant Q and T — plus that the MFI ∝ Q^n / (P·η(T)) proportions hold exactly
## (n = MfiProxy.DIE_FLOW_INDEX, the power-law die's index: on 2026-09-25 the die
## plate it reads went from linear in Q to Q^n, and the proxy's Q term with it).

var _fail := 0
var _pass := 0

func _init() -> void:
	print("=== MfiProxy proxy verification (task #46) ===")
	_test_inverse_pressure()
	_test_proportions()
	_test_temperature_term()
	_test_viscosity_or_temp_dispatch()
	_test_edge_cases()
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _approx(a: float, b: float, eps := 1e-4) -> bool:
	return absf(a - b) <= eps

# -----------------------------------------------------------------------------
# 1) HEADLINE: at constant Q + T, predicted_mfi is INVERSELY related to P_die.
#    Falling die pressure must raise the predicted MFI, monotonically.
# -----------------------------------------------------------------------------
func _test_inverse_pressure() -> void:
	print("\n[1] predicted_mfi rises as die_pressure falls (constant Q, T)")
	var mfi := MfiProxy.new()
	const Q := 950.0
	const T := 215.0

	var p_high := mfi.update(Q, 320.0, T)
	var p_mid  := mfi.update(Q, 250.0, T)
	var p_low  := mfi.update(Q, 180.0, T)

	_ok(p_high > 0.0 and p_mid > 0.0 and p_low > 0.0,
		"all three pressures give a positive MFI (%.3f / %.3f / %.3f)" % [p_high, p_mid, p_low])
	_ok(p_mid > p_high, "250 bar MFI (%.3f) > 320 bar MFI (%.3f)" % [p_mid, p_high])
	_ok(p_low > p_mid,  "180 bar MFI (%.3f) > 250 bar MFI (%.3f)" % [p_low, p_mid])
	# Strictly monotonic decreasing in pressure across a sweep.
	var prev := INF
	var monotonic := true
	for p in [120.0, 160.0, 200.0, 260.0, 320.0, 400.0]:
		var v := mfi.update(Q, p, T)
		if v >= prev:
			monotonic = false
		prev = v
	_ok(monotonic, "MFI strictly decreases across a rising-pressure sweep")
	# update() caches its result into predicted_mfi.
	mfi.update(Q, 250.0, T)
	_ok(_approx(mfi.predicted_mfi, p_mid), "predicted_mfi cached == returned value (%.3f)" % mfi.predicted_mfi)

# -----------------------------------------------------------------------------
# 2) The exact proportions of MFI ∝ Q / (P · η).
# -----------------------------------------------------------------------------
func _test_proportions() -> void:
	print("\n[2] MFI ∝ Q^n / (P · η) proportions hold")
	var mfi := MfiProxy.new()
	const T := 215.0
	var n := MfiProxy.DIE_FLOW_INDEX
	# The checks below read n from the proxy itself, so on their own they
	# follow ANY exponent (measured 2026-09-25: with DIE_FLOW_INDEX forced to
	# 1.0 they stayed 21 ok). This one pins it to the die it is read against.
	_ok(is_equal_approx(n, ExtruderScrew.POWER_LAW_N),
		"Q exponent %.2f == the die plate's flow index ExtruderScrew.POWER_LAW_N %.2f" % [n, ExtruderScrew.POWER_LAW_N])

	var base := mfi.update(900.0, 240.0, T)

	# Q^n: doubling throughput scales MFI by 2^n (P, T fixed), not 2x. A
	# power-law die needs Q^n of pressure, so a linear Q would read a faster
	# line on the same melt as a runnier one.
	var double_q := mfi.update(1800.0, 240.0, T)
	_ok(_approx(double_q, base * pow(2.0, n), base * 1e-3),
		"2x throughput → 2^%.2f = %.4fx MFI (%.4f vs %.4f)" % [n, pow(2.0, n), double_q, base * pow(2.0, n)])
	# The pair the proxy is read against: the power-law die at 2x flow needs
	# 2^n x the pressure, and the MFI does not move.
	var die_pair := mfi.update(1800.0, 240.0 * pow(2.0, n), T)
	_ok(_approx(die_pair, base, base * 1e-4),
		"2x flow at the power-law die's 2^n pressure → same MFI (%.4f vs %.4f)" % [die_pair, base])

	# Inverse in P: halving die pressure doubles MFI (Q, T fixed).
	var half_p := mfi.update(900.0, 120.0, T)
	_ok(_approx(half_p, base * 2.0, base * 1e-3),
		"0.5x die pressure → 2x MFI (%.4f vs %.4f)" % [half_p, base * 2.0])

	# Inverse in η: tripling viscosity thirds the MFI (Q, P fixed, η passed direct).
	var eta_base := mfi.update(900.0, 240.0, 1.0)
	var eta_3x   := mfi.update(900.0, 240.0, 3.0)
	_ok(_approx(eta_3x, eta_base / 3.0, eta_base * 1e-3),
		"3x viscosity → 1/3 MFI (%.4f vs %.4f)" % [eta_3x, eta_base / 3.0])

	# Combined: product rule. Q×k_q, P×k_p, η×k_e → MFI × (k_q^n / (k_p·k_e)).
	var combo := mfi.update(900.0 * 1.5, 240.0 * 2.0, 2.0)   # eta_base had η=1.0
	var expected := eta_base * (pow(1.5, n) / (2.0 * 2.0))
	_ok(_approx(combo, expected, eta_base * 1e-3),
		"combined Q/P/η scaling matches product rule (%.4f vs %.4f)" % [combo, expected])

# -----------------------------------------------------------------------------
# 3) η(T): hotter melt is runnier → higher MFI at constant Q, P. And the
#    Arrhenius decade halves viscosity (so it doubles MFI) every TEMP_DECADE_C.
# -----------------------------------------------------------------------------
func _test_temperature_term() -> void:
	print("\n[3] temperature term η(T): hotter → higher MFI")
	var mfi := MfiProxy.new()
	const Q := 900.0
	const P := 240.0

	var cold := mfi.update(Q, P, 195.0)
	var hot  := mfi.update(Q, P, 235.0)
	_ok(hot > cold, "235 °C MFI (%.3f) > 195 °C MFI (%.3f)" % [hot, cold])

	# At the reference temperature, η == VISCOSITY_REF (1.0), so the temp path and
	# the direct-viscosity path agree exactly.
	var at_ref_temp     := mfi.update(Q, P, MfiProxy.REF_TEMP_C)
	var at_ref_eta      := mfi.update(Q, P, MfiProxy.VISCOSITY_REF)
	_ok(_approx(at_ref_temp, at_ref_eta),
		"η(REF_TEMP)==VISCOSITY_REF → temp & viscosity paths agree (%.4f)" % at_ref_temp)

	# One decade hotter halves η → doubles MFI.
	var ref_mfi    := mfi.update(Q, P, MfiProxy.REF_TEMP_C)
	var decade_mfi := mfi.update(Q, P, MfiProxy.REF_TEMP_C + MfiProxy.TEMP_DECADE_C)
	_ok(_approx(decade_mfi, ref_mfi * 2.0, ref_mfi * 1e-3),
		"+%.0f °C halves η → 2x MFI (%.4f vs %.4f)" % [MfiProxy.TEMP_DECADE_C, decade_mfi, ref_mfi * 2.0])

# -----------------------------------------------------------------------------
# 4) The flexible 3rd arg: big number = temperature (°C), small = viscosity.
# -----------------------------------------------------------------------------
func _test_viscosity_or_temp_dispatch() -> void:
	print("\n[4] viscosity_or_temp dispatch (temp vs raw viscosity)")
	# A melt-temperature value resolves through viscosity_at_temp().
	_ok(_approx(MfiProxy.resolve_viscosity(215.0), MfiProxy.viscosity_at_temp(215.0)),
		"215 (> threshold) resolves as a TEMPERATURE")
	# A small value passes straight through as a viscosity.
	_ok(_approx(MfiProxy.resolve_viscosity(1.5), 1.5),
		"1.5 (< threshold) resolves as a raw VISCOSITY")
	# viscosity_at_temp falls with temperature.
	_ok(MfiProxy.viscosity_at_temp(240.0) < MfiProxy.viscosity_at_temp(200.0),
		"viscosity_at_temp decreases with temperature")

# -----------------------------------------------------------------------------
# 5) Edge cases — no divide-by-zero, no negative/odd output.
# -----------------------------------------------------------------------------
func _test_edge_cases() -> void:
	print("\n[5] edge cases")
	var mfi := MfiProxy.new()
	_ok(_approx(mfi.update(0.0, 250.0, 215.0), 0.0), "Q=0 → MFI 0 (no melt flowing)")
	var zero_p := mfi.update(900.0, 0.0, 215.0)
	_ok(is_finite(zero_p) and zero_p > 0.0, "P=0 stays finite (%.1f) — denominator floored" % zero_p)
	_ok(_approx(mfi.update(900.0, 250.0, 0.0), 0.0), "η=0 → MFI 0 (guarded)")
	# normalized() stays in 0..1 across extremes.
	mfi.update(5000.0, 50.0, 260.0)        # very runny
	var n_hi := mfi.normalized()
	mfi.update(50.0, 600.0, 150.0)         # very stiff
	var n_lo := mfi.normalized()
	_ok(n_hi >= 0.0 and n_hi <= 1.0 and n_lo >= 0.0 and n_lo <= 1.0,
		"normalized() clamped to 0..1 (hi %.2f, lo %.2f)" % [n_hi, n_lo])
	_ok(n_hi > n_lo, "runny melt normalizes higher than stiff melt")
