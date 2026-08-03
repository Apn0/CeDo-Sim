extends Node
## Proof for the #macro-sink corruption guard (LineMacroStore.delta_sane + the
## save-back / load filters).
##
## Root cause of the line_3a FAIL: machine 32 physically sank to y≈-27 km (a
## physics fall), the macro save recorded its plummeting Y as dy, and the delta
## compounded every save→load→fall cycle (-27 km → -40 km). The guard makes a
## glitched/sinking machine unable to poison a macro on either save or load.
##
##   godot --headless --path <proj> --main-scene res://src/tests/test_macro_delta_guard.tscn

var _fails : int = 0

func _check(cond: bool, msg: String) -> void:
	print(("  ok    : " if cond else "  FAIL  : ") + msg)
	if not cond:
		_fails += 1

func _ready() -> void:
	print("=== Macro delta corruption guard ===")
	var store = get_node_or_null("/root/LineMacroStore")
	if store == null:
		# Fall back to a fresh instance if the autoload isn't mounted.
		store = preload("res://src/autoload/LineMacroStore.gd").new()
		add_child(store)

	# --- predicate: rejects the exact corruption, keeps legit deltas ---
	_check(store.delta_sane(1.0, 2.0, 3.0, 0.5), "sane small delta accepted")
	_check(store.delta_sane(82.5, 1.42, 1.34, 0.0), "real line_3a sane entry accepted (dx=82.5)")
	_check(not store.delta_sane(0.0, -27136.5, 0.0, 0.0), "corrupt 08:04 dy=-27136 REJECTED")
	_check(not store.delta_sane(0.0, -40696.5, 0.0, 0.0), "corrupt live dy=-40696 REJECTED")
	_check(not store.delta_sane(0.0, INF, 0.0, 0.0), "non-finite INF rejected")
	_check(not store.delta_sane(0.0, NAN, 0.0, 0.0), "non-finite NAN rejected")
	_check(store.delta_sane(0.0, 99.9, 0.0, 0.0), "at-cap 99.9 m accepted")
	_check(not store.delta_sane(0.0, 100.1, 0.0, 0.0), "just over 100 m cap rejected")

	# --- load filter: get_overrides drops the poisoned entry, keeps the rest ---
	store._cache["line_3a"] = {
		"deltas": {
			"0":  {"dx": 1.0, "dy": 2.0, "dz": 3.0, "drot_y": 0.0, "scale": [1.0, 1.0, 1.0]},
			"32": {"dx": 0.0, "dy": -27136.5, "dz": 0.0, "drot_y": 0.0, "scale": [1.0, 1.0, 1.0]},
		},
	}
	var ov : Dictionary = store.get_overrides("line_3a")
	_check(ov.has(0), "load keeps the sane index 0")
	_check(not ov.has(32), "load DROPS the poisoned index 32 (dy=-27136)")

	print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)
