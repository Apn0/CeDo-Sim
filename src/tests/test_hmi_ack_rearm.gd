extends Node
## HMI FAULT ACK RE-ARMS ON CLEAR (2026-09-24, C6) — KWITTEREN acknowledges an
## OCCURRENCE, not a fault code forever.
##
##   godot --headless --path . res://src/tests/test_hmi_ack_rearm.tscn
##
## HmiOverlay kept `_acked_faults` keyed by code and cleared it only on
## RESETTEN. A fault that cleared by itself and then tripped again came back
## already acknowledged: no unacked row on the ACTIVE tab, the bell calm.
## Trigger: RUN-200 active -> KWITTEREN -> condition ends -> condition returns.
## The real overlay class is driven (its own _compute_faults ->
## _record_fault_transitions), with a stub LineFlow so the PLC-000 "no PLC"
## row does not stand in for the fault under test.
##
## Measured before the fix (mutation: the `_acked_faults.erase(code)` line
## removed): check 4 and 5 red — the re-trip reported acked=true.

const WATCHDOG_S := 60.0
const CODE := "RUN-200"   # "Leegdraaien actief" — a row the overlay raises off its own flag

var _fails := 0
var _oks := 0

class StubLineFlow extends Node:
	var fed_mass : float = 0.0
	var _nodes : Array = []

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

func _codes(faults: Array) -> Array:
	var out := []
	for f in faults:
		out.append(String(f.get("code", "")))
	return out

## True when CODE shows as an UNACKED row on the ACTIVE tab (the tab that
## hides acked rows) — what the operator actually sees.
func _unacked_row(ov, faults: Array) -> bool:
	ov._fault_tab = ov.FaultTab.ACTIVE
	for r in ov._rows_for_tab(faults):
		if String(r.get("code", "")) == CODE:
			return true
	return false

func _run() -> void:
	print("[TEST] HMI fault ack re-arms when the fault clears")
	var stub := StubLineFlow.new()
	stub.add_to_group("line_flow")
	add_child(stub)
	var ov = load("res://src/scenes/hud/HmiOverlay.gd").new()
	add_child(ov)
	ov._line_flow = stub

	ov._leegdraaien = true
	var f1 : Array = ov._compute_faults()
	_check(_codes(f1).has(CODE) and not _codes(f1).has("PLC-000"),
		"1 the fault under test is live (%s) and no PLC-000 stands in for it" % str(_codes(f1)))
	_check(_unacked_row(ov, f1), "2 a fresh occurrence is an UNACKED row")

	ov._on_kwitteren()
	var f2 : Array = ov._compute_faults()
	_check(not _unacked_row(ov, f2),
		"3 KWITTEREN acknowledges it, and the ack HOLDS while the fault stays active (negative control)")

	ov._leegdraaien = false
	var f3 : Array = ov._compute_faults()
	_check(not _codes(f3).has(CODE), "the condition ended — %s cleared" % CODE)

	ov._leegdraaien = true
	var f4 : Array = ov._compute_faults()
	_check(not ov._acked_faults.has(CODE),
		"4 the re-trip is a NEW occurrence — its code is not in the ack table")
	_check(_unacked_row(ov, f4),
		"5 the re-trip shows as an UNACKED row on the ACTIVE tab (was hidden as acked)")

	ov._on_kwitteren()
	ov._on_reset_faults()
	_check(ov._acked_faults.is_empty(), "6 RESETTEN still empties the ack table")
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] hmi ack re-arm %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
