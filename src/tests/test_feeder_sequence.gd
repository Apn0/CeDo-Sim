extends Node
# #233 — proves the FeederWorker DRIVE sequence follows the operator's real order:
#   • SCAN (actually scan the label) happens BEFORE the wire-cut
#   • CUT (cut the top wires while the clamp still holds the stack) → REMOUNT, i.e.
#     the bale is placed on the conveyor only AFTER the worker climbs back into the
#     clamp — not straight from the cut.
# Run: godot --headless --path . res://src/tests/test_feeder_sequence.tscn
var _fails := 0
func _check(c: bool, m: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + m)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] feeder sequence")
	var fw = load("res://src/scenes/world/FeederWorker.gd").new()
	add_child(fw)
	await get_tree().process_frame
	var bale := Node3D.new()
	bale.add_to_group("bale")
	add_child(bale)
	fw.set("_bale", bale)

	# ── SCAN first (bale still clamped) ──────────────────────────────────────
	fw.set("_timer", 0.0)
	fw.call("_drive_state_scan", 0.1)
	_check(bool(bale.get_meta("scanned", false)), "scan sets 'scanned' (actually scans the label)")
	_check(not bool(bale.get_meta("wires_cut", false)), "wires NOT cut yet — SCAN happens BEFORE CUT")
	_check(int(fw.get("_state")) == FeederWorker.State.CUT, "scan → CUT")

	# ── CUT next → REMOUNT (place only after getting back in the clamp) ───────
	fw.set("_timer", 0.0)
	fw.call("_drive_state_cut", 0.1)
	_check(bool(bale.get_meta("wires_cut", false)), "cut sets 'wires_cut' (cuts the top wires while clamped)")
	_check(int(fw.get("_state")) == FeederWorker.State.REMOUNT,
		"cut → REMOUNT — get back in the clamp BEFORE placing (not straight to FEED)")

	if _fails == 0:
		print("[TEST] feeder sequence PASS")
	else:
		print("[TEST] feeder sequence FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
