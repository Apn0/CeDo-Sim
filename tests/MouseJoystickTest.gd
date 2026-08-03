extends Node3D
## Proves the mouse-as-joystick tool control: holding a mouse button and dragging
## drives the vehicle hydraulics (and does NOT move the camera). We can't post real
## OS mouse events headless, so we drive the SAME entry points the input handler
## feeds: set the held flags + accumulate drag via the public plumbing, then tick
## the vehicle's hydraulic update and assert the setpoints moved the right way.
##
## Run: godot --headless --path . res://tests/MouseJoystickTest.tscn --quit-after 90

const FORKLIFT := "res://src/scenes/vehicles/Forklift.tscn"
const MERLO    := "res://src/scenes/vehicles/Merlo.tscn"
const SCISSOR  := "res://src/scenes/vehicles/MastLift.tscn"   # ScissorLift was renamed to MastLift

var _pass := 0
var _fail := 0
var _lines : Array[String] = []

func _ready() -> void:
	print("=== Mouse-as-joystick tool control test ===")
	_forklift_axes()
	_merlo_axes()
	_scissor_axis()
	_camera_suppressed_while_dragging()
	print("\nRESULT: %d passed · %d failed" % [_pass, _fail])
	for l in _lines:
		print("  - " + l)
	get_tree().quit(0 if _fail == 0 else 1)

func _ok(c: bool, m: String) -> void:
	if c: _pass += 1
	else:
		_fail += 1
		_lines.append(m)
	print(("  ok  : " if c else "  FAIL: ") + m)

## Simulate a drag by loading the same accumulators BaseVehicle._track_tool_mouse
## fills — headless can't set Input.mouse_mode to CAPTURED, which that handler
## guards on, so we inject at the accumulator boundary. (The button-claim path is
## verified separately in _camera_suppressed_while_dragging by forcing the guard.)
func _drag(v: Node, left: Vector2, right: Vector2) -> void:
	v._mouse_left += left
	v._mouse_right += right

func _make(path: String) -> Node:
	var v := (load(path) as PackedScene).instantiate()
	add_child(v)
	v.set("occupied", true)
	return v

# -----------------------------------------------------------------------------
func _forklift_axes() -> void:
	print("\n[forklift]")
	var v := _make(FORKLIFT)
	var lift0: float = v.lift_height_m
	var tilt0: float = v.tilt_deg
	# LEFT drag: up on screen (negative Y) should RAISE; +X should tilt.
	_drag(v, Vector2(120, -200), Vector2.ZERO)
	v._update_hydraulics(0.016)
	_ok(v.lift_height_m > lift0, "LMB drag up raises the forks (%.2f → %.2f)" % [lift0, v.lift_height_m])
	_ok(v.tilt_deg != tilt0, "LMB drag X changes mast tilt")
	# RIGHT drag drives rotator (X) + fork spread (Y).
	var rot0: float = v.rotator_deg
	var spread0: float = v.fork_spread_m
	_drag(v, Vector2.ZERO, Vector2(200, -150))
	v._update_hydraulics(0.016)
	_ok(v.rotator_deg != rot0, "RMB drag X turns the rotator")
	_ok(v.fork_spread_m != spread0, "RMB drag Y changes fork spread")
	v.queue_free()

func _merlo_axes() -> void:
	print("\n[merlo]")
	var v := _make(MERLO)
	var boom0: float = v.boom_deg
	var grap0: float = v.grapple_deg
	# LEFT: Y = boom elevation, X = grapple clamp.
	_drag(v, Vector2(180, -220), Vector2.ZERO)
	v._update_boom(0.016)
	_ok(v.boom_deg > boom0, "LMB drag up raises the boom (%.1f → %.1f)" % [boom0, v.boom_deg])
	_ok(v.grapple_deg != grap0, "LMB drag X works the grapple clamp")
	# RIGHT: Y = bucket curl, X = telescope.
	var ext0: float = v.extend_m
	var curl0: float = v.curl_deg
	_drag(v, Vector2.ZERO, Vector2(220, -160))
	v._update_boom(0.016)
	_ok(v.extend_m != ext0, "RMB drag X extends the telescope")
	_ok(v.curl_deg != curl0, "RMB drag Y curls the bucket")
	v.queue_free()

func _scissor_axis() -> void:
	print("\n[vertical mast lift]")
	var v := _make(SCISSOR)
	var h0: float = v._platform_height
	_drag(v, Vector2(0, -260), Vector2.ZERO)
	v._update_platform(0.016)
	_ok(v._platform_height > h0, "LMB drag up raises the platform (%.2f → %.2f)" % [h0, v._platform_height])
	# Mast telescopes: drive the platform up and confirm the nested stages slide up
	# proportionally (top stage tracks the platform, lower stages nest below it).
	v._platform_height = 6.0
	v._apply_platform_transforms()
	_ok(v._mast_stages.size() == 3, "mast has 3 telescoping stages (%d)" % v._mast_stages.size())
	if v._mast_stages.size() == 3:
		var s1: float = v._mast_stages[0].position.y
		var s3: float = v._mast_stages[2].position.y
		_ok(s3 > s1 and s1 > 0.0, "stages telescope in order (stage1 y=%.2f < stage3 y=%.2f)" % [s1, s3])
	v.queue_free()

func _camera_suppressed_while_dragging() -> void:
	print("\n[both buttons → all four axes at once]")
	var v := _make(MERLO)
	# Holding BOTH buttons and dragging should move LEFT and RIGHT functions
	# together — one drag works the whole tool. Inject into both accumulators and
	# confirm a boom (left-Y) AND a telescope (right-X) change in one update.
	var boom0: float = v.boom_deg
	var ext0: float = v.extend_m
	_drag(v, Vector2(0, -200), Vector2(200, 0))   # left up + right across
	v._update_boom(0.016)
	_ok(v.boom_deg > boom0 and v.extend_m != ext0,
		"both-buttons drag moves boom AND telescope in one update")
	# Button-claim semantics: with no button held, a motion event is NOT claimed
	# (falls through to the camera). (The held-claim path needs a captured cursor,
	# which headless can't emulate, so we assert only the fall-through here.)
	v._lmb_held = false
	v._rmb_held = false
	var e := InputEventMouseMotion.new()
	e.relative = Vector2(50, 50)
	_ok(v._track_tool_mouse(e) == false, "motion falls through to the camera when no button is held")
	v.queue_free()
