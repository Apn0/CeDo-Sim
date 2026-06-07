extends SceneTree

const _ScanLog := preload("res://src/autoload/ScanLog.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — ScanLog headless test")
	print("============================================================")

	_test_initialization()
	_test_append_entry()
	_test_max_entries()
	_test_total_kg()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")

	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

func _test_initialization() -> void:
	print("[1] Initialization")
	var log_node := _ScanLog.new()
	_ok(log_node.count() == 0, "ScanLog starts empty")
	log_node.queue_free()

func _test_append_entry() -> void:
	print("[2] Append entry")
	var log_node := _ScanLog.new()
	log_node._on_bale_scanned({"id": "BALE_1", "weight_kg": 500.0})
	_ok(log_node.count() == 1, "ScanLog count is 1 after scan")
	_ok(log_node.total_kg() == 500.0, "ScanLog total_kg is 500.0")
	log_node.queue_free()

func _test_max_entries() -> void:
	print("[3] MAX_ENTRIES limit")
	var log_node := _ScanLog.new()
	var limit : int = log_node.MAX_ENTRIES

	for i in range(limit + 10):
		log_node._on_bale_scanned({"id": "BALE_%d" % i, "weight_kg": 100.0})

	_ok(log_node.count() == limit, "ScanLog caps at MAX_ENTRIES (%d)" % limit)
	_ok(log_node.total_kg() == float(limit * 100.0), "Total kg only counts the kept entries")
	log_node.queue_free()

func _test_total_kg() -> void:
	print("[4] Total KG sum")
	var log_node := _ScanLog.new()
	log_node._on_bale_scanned({"weight_kg": 200.0})
	log_node._on_bale_scanned({"weight_kg": 150.5})
	log_node._on_bale_scanned({"weight_kg": 49.5})

	_ok(log_node.total_kg() == 400.0, "ScanLog total_kg correctly sums values")
	log_node.queue_free()
