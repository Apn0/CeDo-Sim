extends Node3D

## Headless test for in-cabin item placement (#162): CabinProp items build with
## the right tool_id, and the cup-holder accept-filter only lets a coffee snap
## in (a sandwich is rejected).

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	await _test_props_build()
	_test_slot_accept_filter()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _make_prop(kind: String) -> Node3D:
	var p : Node3D = preload("res://src/scenes/world/CabinProp.gd").new()
	p.prop_kind = kind
	add_child(p)
	return p

func _test_props_build() -> void:
	print("[1] CabinProp coffee + sandwich build with correct tool_id")
	var coffee = _make_prop("coffee")
	var sandwich = _make_prop("sandwich")
	await get_tree().process_frame
	_ok(String(coffee.get("tool_id")) == "coffee", "coffee tool_id set")
	_ok(String(sandwich.get("tool_id")) == "sandwich", "sandwich tool_id set")
	_ok(coffee.is_in_group("cabin_prop"), "coffee joined the cabin_prop group")
	_ok(coffee.get_node_or_null("PickupArea") != null, "coffee has a pickup trigger")

func _test_slot_accept_filter() -> void:
	print("[2] cup-holder accepts coffee, rejects sandwich")
	var placer : Node = preload("res://src/build/ToolPlacementMode.gd").new()
	add_child(placer)
	# A cup-holder slot (accepts coffee only) and a generic slot (accepts all).
	var cup := Node3D.new()
	cup.set_meta("accepts", ["coffee"])
	add_child(cup)
	var generic := Node3D.new()
	add_child(generic)
	var coffee = _make_prop("coffee")
	var sandwich = _make_prop("sandwich")
	_ok(placer._slot_accepts(cup, coffee), "cup holder accepts a coffee")
	_ok(not placer._slot_accepts(cup, sandwich), "cup holder REJECTS a sandwich")
	_ok(placer._slot_accepts(generic, sandwich), "generic slot accepts a sandwich")
	_ok(placer._slot_accepts(generic, coffee), "generic slot accepts a coffee")
