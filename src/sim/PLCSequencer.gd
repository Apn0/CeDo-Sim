extends Node
class_name PLCSequencer

## Models the PLC START ORDER the operator flagged: machines don't all power on
## at once — the line powers up DOWNSTREAM-FIRST (so there's somewhere for
## material to go) with a stagger between each, and powers down in REVERSE
## (upstream-first) so nothing is left buried. Each stage optionally drives a
## target that has `set_running(bool)` (e.g. a RotatingMechanism or a machine).
##
## Usage:
##   var plc := PLCSequencer.new()
##   plc.stagger_s = 1.5
##   for m in machines_in_flow_order: plc.add_stage(m)   # head … tail order
##   plc.start()      # powers tail → head, one every stagger_s
##   ... plc.tick(delta) each frame ...
##   plc.stop()       # powers head → tail off

@export var stagger_s : float = 1.5

var _stages   : Array = []     # [{powered:bool, target:Object}]
var _phase    : int   = 0      # 0 idle, 1 starting, -1 stopping
var _idx      : int   = 0
var _timer    : float = 0.0

# =============================================================================
## Add a stage in FLOW order (head first, tail last). Power-up walks this list
## in reverse (tail first); power-down walks it forward (head first).
func add_stage(target: Object = null) -> void:
	_stages.append({"powered": false, "target": target})

func start() -> void:
	if _stages.is_empty():
		return
	_phase = 1
	_idx = _stages.size() - 1   # downstream (tail) powers up first
	_timer = 0.0

func stop() -> void:
	if _stages.is_empty():
		return
	_phase = -1
	_idx = 0                     # upstream (head) powers down first
	_timer = 0.0

func tick(delta: float) -> void:
	if _phase == 0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	if _phase == 1:
		if _idx >= 0:
			_power_stage(_idx, true)
			_idx -= 1
			_timer = stagger_s
		if _idx < 0:
			_phase = 0           # fully started
	elif _phase == -1:
		if _idx < _stages.size():
			_power_stage(_idx, false)
			_idx += 1
			_timer = stagger_s
		if _idx >= _stages.size():
			_phase = 0           # fully stopped

func _power_stage(i: int, on: bool) -> void:
	if i < 0 or i >= _stages.size():
		return
	_stages[i]["powered"] = on
	var t = _stages[i]["target"]
	if t != null and t.has_method("set_running"):
		t.call("set_running", on)

# ── Queries ───────────────────────────────────────────────────────────────────
func powered_count() -> int:
	var n := 0
	for s in _stages:
		if s["powered"]:
			n += 1
	return n

func is_powered(i: int) -> bool:
	return i >= 0 and i < _stages.size() and bool(_stages[i]["powered"])

func all_running() -> bool:
	return powered_count() == _stages.size() and _stages.size() > 0

func all_stopped() -> bool:
	return powered_count() == 0

func is_busy() -> bool:
	return _phase != 0
