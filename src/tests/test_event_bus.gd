extends SceneTree

const EventBusScript = preload("res://src/autoload/EventBus.gd")

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

func _initialize() -> void:
	print("=== EventBus verification ===")

	var bus = EventBusScript.new()
	bus.name = "EventBus"
	root.add_child(bus)

	# ── 1. Signal Existence ──────────────────────────────────────────────
	_section("Signal Existence")
	_ok(bus.has_signal("machine_state_changed"), "has machine_state_changed signal")
	_ok(bus.has_signal("scada_event"), "has scada_event signal")
	_ok(bus.has_signal("player_interacted"), "has player_interacted signal")
	_ok(bus.has_signal("shift_started"), "has shift_started signal")
	_ok(bus.has_signal("bale_scanned"), "has bale_scanned signal")

	# ── 2. Signal Emission ───────────────────────────────────────────────
	_section("Signal Emission")

	var state_events := []
	bus.machine_state_changed.connect(func(machine_id, old_state, new_state):
		state_events.append({"id": machine_id, "old": old_state, "new": new_state})
	)
	bus.machine_state_changed.emit("extruder_1", 0, 1)
	_ok(state_events.size() == 1, "machine_state_changed fired once")
	if state_events.size() == 1:
		_ok(state_events[0]["id"] == "extruder_1", "machine_state_changed carries correct id")
		_ok(state_events[0]["old"] == 0, "machine_state_changed carries correct old_state")
		_ok(state_events[0]["new"] == 1, "machine_state_changed carries correct new_state")

	var scada_events := []
	bus.scada_event.connect(func(line_id, event_name, data):
		scada_events.append({"line": line_id, "name": event_name, "data": data})
	)
	var test_data = {"key": "val"}
	bus.scada_event.emit("3A", "test_event", test_data)
	_ok(scada_events.size() == 1, "scada_event fired once")
	if scada_events.size() == 1:
		_ok(scada_events[0]["line"] == "3A", "scada_event carries correct line_id")
		_ok(scada_events[0]["name"] == "test_event", "scada_event carries correct event_name")
		_ok(scada_events[0]["data"]["key"] == "val", "scada_event carries correct data")

	var interaction_events := []
	bus.player_interacted.connect(func(target, interaction):
		interaction_events.append({"target": target, "interaction": interaction})
	)
	var mock_node = Node.new()
	root.add_child(mock_node)
	bus.player_interacted.emit(mock_node, "push")
	_ok(interaction_events.size() == 1, "player_interacted fired once")
	if interaction_events.size() == 1:
		_ok(interaction_events[0]["target"] == mock_node, "player_interacted carries correct target node")
		_ok(interaction_events[0]["interaction"] == "push", "player_interacted carries correct interaction string")

	mock_node.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)
