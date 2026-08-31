extends SceneTree
## #A3 — the silo level sensor must actually get SiloLevelSensor.gd attached.
##
## Run: godot --headless --path . --script res://src/tests/test_silo_level_sensor_wired.gd --quit-after 300
##
## WHY THIS EXISTS. PlaceableCatalog.build_node() picks the body class from a
## long if/elif chain. `silo_level_sensor`'s category is "Control", and the
## `category == "Control"` arm used to be tested BEFORE the `id ==
## "silo_level_sensor"` arm — so the id arm was unreachable and every placed
## sensor got Hmi.gd instead. That one line was the ONLY instantiation of
## SiloLevelSensor.gd in the repo, so LineFlow's
## get_nodes_in_group("silo_level_sensor") lookup (LineFlow.gd:410) was
## permanently empty and the #A3 throttle mechanic had never run in any build.
## TagMap.gd:60 had already recorded the downstream symptom without anyone
## tracing it to the ordering.
##
## An ordering bug like this is invisible to a parse check and to any test that
## only asks "does the catalog have an entry" — it needs the node BUILT.

const PlaceableCatalog = preload("res://src/build/PlaceableCatalog.gd")

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== #A3 silo level sensor wiring ===")

	var item := PlaceableCatalog.get_item("silo_level_sensor")
	var has_item: bool = item != null and not item.is_empty()
	_ok(has_item, "silo_level_sensor is in the catalog")
	# Guarded: a counted check does not abort, so indexing a null item below
	# would crash before the verdict prints — the hang bug in a new hat.
	_ok(has_item and String(item.get("category", "")) == "Control",
		"its category is still Control (the condition that made the arm unreachable)")

	var node := PlaceableCatalog.build_node("silo_level_sensor")
	_ok(node != null, "build_node returns a node")

	# THE CLAIM. Not "a script is attached" — the RIGHT script. Hmi.gd is what it
	# silently got before, and Hmi.gd is also a perfectly valid body class here,
	# so a weaker check would have passed throughout the entire dead period.
	var scr: Script = null
	if node != null:
		scr = node.get_script()
	var scr_path: String = "" if scr == null else scr.resource_path
	_ok(scr != null, "the built body carries a script")
	_ok(scr_path == "res://src/sim/SiloLevelSensor.gd",
		"the script is SiloLevelSensor.gd, not Hmi.gd (got: %s)" % ["<none>" if scr_path == "" else scr_path])

	# The behaviour LineFlow actually reaches for.
	_ok(node != null and node.has_method("wants_throttle"),
		"exposes wants_throttle() — what upstream feed scripts call")

	# LineFlow._index_silo_sensors() (LineFlow.gd:410-420) finds these BY GROUP,
	# and SiloLevelSensor.gd:77 joins that group in _ready() — which only fires on
	# tree entry. So the node must actually be added to the tree before asking:
	# checking straight off build_node() reports a false failure (measured, this
	# test did exactly that first time round).
	if node != null:
		root.add_child(node)
	_ok(node != null and node.is_in_group("silo_level_sensor"),
		"joins the silo_level_sensor group LineFlow looks it up by, once in the tree")

	if node != null:
		root.remove_child(node)
		node.free()
	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
