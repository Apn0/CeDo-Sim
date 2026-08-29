extends Node
## Shredder throughput reconciliation — guards the 2026-08-29 fix.
##
##   godot --headless --path . res://src/tests/test_shredder_rate_reconciliation.tscn
##
## Audit findings H6/H16 (docs/plant/DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md and
## the earlier DETAIL_STANDARD audit) flagged that shredder_1/shredder_2 had
## TWO independent, disagreeing capacity models on the same node:
## ShredderMachine.gd's doc-grounded RATED_COARSE/RATED_FINE (4500/2200 kg/h,
## whole-plant mass-balance figures) sat unread while the production ledger
## (MachineFlow.profile → LineFlow) fell through to a generic 6.0 kg/s
## (21,600 kg/h) default — 4.8x looser. Measured consequence: a single bale
## dumped on line 1's infeed sailed straight through shredder_1 and tripped
## the unrelated downstream 'mill' node instead of the shredder itself, the
## natural bottleneck for a bulk dump.
##
## S1 proves the two numbers can never silently diverge again. S2 sanity-
## checks the operator's 2026-08-29 knife-geometry estimate (75 rotor knives,
## 15 stator knives / ~5 m total edge, 30 rpm min) against RATED_COARSE — a
## wide band, not a tight pin, since every input is a rough live estimate.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] shredder rate reconciliation")

	# ── S1 — MachineFlow reads ShredderMachine's rated capacity directly ─────
	print("  -- S1: rate reconciliation (H6/H16) --")
	var r1 : float = float(MachineFlow.profile("shredder_1")["rate"])
	var r2 : float = float(MachineFlow.profile("shredder_2")["rate"])
	_check(is_equal_approx(r1, ShredderMachine.RATED_COARSE / 3600.0),
		"shredder_1's MachineFlow rate matches ShredderMachine.RATED_COARSE (%.4f kg/s == %.4f kg/s)"
		% [r1, ShredderMachine.RATED_COARSE / 3600.0])
	_check(is_equal_approx(r2, ShredderMachine.RATED_FINE / 3600.0),
		"shredder_2's MachineFlow rate matches ShredderMachine.RATED_FINE (%.4f kg/s == %.4f kg/s)"
		% [r2, ShredderMachine.RATED_FINE / 3600.0])
	# The old default (6.0 kg/s) must be GONE from both — a regression back to
	# it would silently re-open H16 without tripping the equality checks above
	# if someone "fixed" ShredderMachine's constant to 21600 kg/h instead.
	_check(not is_equal_approx(r1, 6.0), "shredder_1 no longer on the generic 6.0 kg/s default")
	_check(not is_equal_approx(r2, 6.0), "shredder_2 no longer on the generic 6.0 kg/s default")
	# 'mill' deliberately UNCHANGED — no real line-1 figure exists (see
	# MachineFlow.gd's comment on the "mill" arm for why the 3C/Lijn-5 amp
	# readings don't transfer). This asserts the non-fix is intentional, not
	# a leftover TODO — if 'mill' ever gets a real number this check should
	# be updated to match it, not deleted.
	_check(is_equal_approx(float(MachineFlow.profile("mill")["rate"]), 6.0),
		"'mill' stays on the generic default — no real line-1 HMI figure exists yet")

	# ── S2 — knife-geometry cross-check lands in a physically sane band ──────
	print("  -- S2: knife-geometry cross-check (operator 2026-08-29 estimate) --")
	var edge_rate : float = ShredderMachine.swept_edge_rate_m_s()
	_check(is_equal_approx(edge_rate, 187.5),
		"swept edge rate = stator_edge(5m) x rotor_knives(75) x rev/s(0.5) = 187.5 m/s (got %.2f)" % edge_rate)
	var chip_depth_mm : float = ShredderMachine.implied_chip_depth_m() * 1000.0
	# Wide sanity band: anywhere from a few microns to a few mm is "a shredder
	# shears a THIN layer per pass, not a solid slab" — the qualitative claim
	# this cross-check exists to test. It is NOT a tight pin on the operator's
	# rough numbers; a value outside this band would mean the geometry inputs
	# and RATED_COARSE are inconsistent by orders of magnitude, worth a look.
	_check(chip_depth_mm > 0.001 and chip_depth_mm < 5.0,
		"implied chip depth is a physically sane thin-shear value (%.4f mm)" % chip_depth_mm)

	print("[TEST] shredder rate reconciliation %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
