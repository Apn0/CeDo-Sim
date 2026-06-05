extends Node3D
class_name CameraRig
## Multi-mode camera attached to a subject (player capsule or vehicle body).
##
## Modes (cycled by tapping F4):
##   FIRST_PERSON   the externally-provided "head/cab" Camera3D is current.
##                  (For the player that's Head/Camera3D; for a vehicle it's
##                  CabCamera.)
##   THIRD_PERSON   the rig's own camera sits at a fixed offset behind+above
##                  the subject and follows it (inherits subject yaw).
##   ORBIT          the rig's camera orbits around the subject in WORLD space
##                  (independent of subject rotation). Pan with arrow keys,
##                  zoom with the mouse wheel — all while F4 is HELD, so the
##                  controls feel like Star Citizen's free-look modifier.
##
## Inputs (only acted on when F4 is held — except for F4-tap which cycles):
##   F4 (tap)              cycle FIRST_PERSON → THIRD_PERSON → ORBIT → FIRST
##   F4 + ←/→              orbit yaw   (THIRD_PERSON yaw is fixed; this is ORBIT-only)
##   F4 + ↑/↓              orbit pitch (ORBIT-only)
##   F4 + scroll up/down   zoom in / out (ORBIT and THIRD_PERSON)
##
## The rig is owned by its subject (parent in the scene tree); the subject calls
## set_first_person_camera() at boot and forwards _process(delta) calls so the
## orbit/follow updates run every frame.

enum Mode { FIRST_PERSON, THIRD_PERSON, ORBIT }

# Tunables — exposed so the Player and the Vehicles can pick different defaults
@export var third_person_offset : Vector3 = Vector3(0.0, 2.0, -5.0)    # behind & above (in subject local space)
@export var orbit_default_dist  : float   = 6.0
@export var orbit_min_dist      : float   = 2.0
@export var orbit_max_dist      : float   = 30.0
@export var orbit_pan_rate      : float   = 1.8         # rad/s while an arrow is held
@export var scroll_zoom_step    : float   = 0.6         # metres per wheel notch

# Constants — independent of any subject
const PITCH_MIN : float = -PI * 0.49
const PITCH_MAX : float =  PI * 0.49

# Runtime state
var _mode               : Mode = Mode.FIRST_PERSON
var _orbit_yaw          : float = 0.0
var _orbit_pitch        : float = -0.25
var _orbit_distance     : float = 6.0
var _f4_held            : bool  = false
var _f4_acted_this_hold : bool  = false   # any modifier action fired since F4 went down

# Cameras: the rig owns one (used in 3rd-person + orbit); the subject hands in
# the first-person one. Both must outlive the rig — we just toggle .current.
var _camera                  : Camera3D
var _first_person_camera     : Camera3D = null

## True when this rig "owns" the viewport — i.e. the player is on foot (player
## rig active) OR is occupying this vehicle (vehicle rig active). The flag
## prevents an unattended vehicle's cab camera from grabbing the viewport just
## because the vehicle spawned. Toggled by activate() / deactivate().
var _active : bool = false

# Cab look-around state (1st-person mouse): cab camera rotates relative to its
# initial transform, so dropping the mouse leaves the operator looking forward.
var _cab_yaw          : float     = 0.0
var _cab_pitch        : float     = 0.0
var _cab_initial_xf   : Transform3D = Transform3D.IDENTITY
const CAB_YAW_LIMIT   : float = PI * 0.95     # almost full circle, can look behind shoulder
const CAB_PITCH_LIMIT : float = PI * 0.48     # ~±86° vertical

# =============================================================================
## We create _camera in _init (not _ready) so it exists the moment the rig is
## constructed — handlers like set_mode() can update its position synchronously
## without waiting for the next idle frame. This also keeps headless --script
## tests working (their SceneTree never processes a frame, so _ready never fires).
func _init() -> void:
	_camera = Camera3D.new()
	_camera.name = "RigCamera"
	_camera.current = false
	add_child(_camera)

func _ready() -> void:
	_orbit_distance = orbit_default_dist
	# Make sure scroll-wheel + arrows actually reach _input even when the player
	# is paused — the menu is on a higher layer; we only listen when F4 is held
	# anyway so there's no clash.
	set_process_unhandled_input(true)
	set_process(true)

## Called by the subject after _ready() to hand in the cab/head camera.
## Stores the reference only — does NOT make it current. The subject calls
## activate() when it wants the rig to actually own the viewport. We also
## snapshot the camera's initial transform so mouse-look offsets are relative
## to "looking forward" instead of slowly drifting away from neutral.
func set_first_person_camera(cam: Camera3D) -> void:
	_first_person_camera = cam
	if cam:
		_cab_initial_xf = cam.transform
	if _active:
		_apply_active_camera()

## Take ownership of the viewport. Activates the current mode's camera.
## Called by PlayerController._ready and by BaseVehicle.on_operator_entered.
func activate() -> void:
	_active = true
	_apply_active_camera()

## Release the viewport. Deactivates BOTH this rig's _camera and the cab/head
## first-person camera, so the next call site (the other rig, on exit/enter)
## can cleanly take over. Called by BaseVehicle.on_operator_exited and by
## PlayerController whenever the player enters a vehicle.
func deactivate() -> void:
	_active = false
	if _first_person_camera and is_instance_valid(_first_person_camera):
		_first_person_camera.current = false
	if _camera and is_instance_valid(_camera):
		_camera.current = false

func is_active() -> bool:
	return _active

# =============================================================================
# MODE CONTROL
# =============================================================================
func cycle_mode() -> void:
	set_mode(((int(_mode) + 1) % 3) as Mode)

func set_mode(m: Mode) -> void:
	_mode = m
	# When entering ORBIT, seed the yaw to match the subject's current facing so
	# the camera doesn't suddenly snap to a new bearing.
	if _mode == Mode.ORBIT:
		_orbit_yaw = wrapf(rotation.y + PI, -PI, PI)
	if _active:
		_apply_active_camera()
	# Update the camera's position NOW (don't wait for _process) so the user
	# sees the camera at the correct place the instant they cycle modes.
	if _mode == Mode.THIRD_PERSON:
		_update_follow_camera()
	elif _mode == Mode.ORBIT:
		_update_orbit_camera()

func mode() -> Mode:
	return _mode

func _apply_active_camera() -> void:
	# Null-guard everything so we're safe to call before _ready or during teardown
	# (e.g. tests, or the operator dismounting mid-frame).
	if _mode == Mode.FIRST_PERSON:
		if _first_person_camera and is_instance_valid(_first_person_camera):
			_first_person_camera.current = true
		if _camera and is_instance_valid(_camera):
			_camera.current = false
	else:
		if _camera and is_instance_valid(_camera):
			_camera.current = true
		if _first_person_camera and is_instance_valid(_first_person_camera):
			_first_person_camera.current = false

# =============================================================================
# FRAME UPDATE — pan + zoom + follow / orbit positioning
# =============================================================================
func _process(delta: float) -> void:
	if _mode == Mode.FIRST_PERSON:
		return
	# Arrow pan + scroll zoom: only while F4 is held (the Star-Citizen modifier
	# pattern — keeps arrows + wheel free for other uses outside camera mode).
	if _f4_held:
		_handle_arrow_pan(delta)
	if _mode == Mode.THIRD_PERSON:
		_update_follow_camera()
	elif _mode == Mode.ORBIT:
		_update_orbit_camera()

func _handle_arrow_pan(delta: float) -> void:
	var yaw_axis := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var pitch_axis := Input.get_action_strength("ui_up")  - Input.get_action_strength("ui_down")
	# Optional per-axis inversion for the external free cam (Settings → Gameplay:
	# "Invert free-cam X / Y"), applied independently.
	var sm := get_node_or_null("/root/SettingsManager")
	if sm:
		var g : Dictionary = sm.gameplay()
		if bool(g.get("invert_cam_x", false)):
			yaw_axis = -yaw_axis
		if bool(g.get("invert_cam_y", false)):
			pitch_axis = -pitch_axis
	if absf(yaw_axis) > 0.001 or absf(pitch_axis) > 0.001:
		_f4_acted_this_hold = true
	# Yaw orbits CCW when ←/→ pressed. Pitch lifts up the camera with ↑.
	_orbit_yaw   += yaw_axis * orbit_pan_rate * delta
	_orbit_pitch  = clampf(_orbit_pitch + pitch_axis * orbit_pan_rate * delta, PITCH_MIN, PITCH_MAX)

## THIRD_PERSON: fixed offset BEHIND the subject (rotates with subject's facing
## so the camera always sits at the back). +Z is the subject's forward.
func _update_follow_camera() -> void:
	# Safe to call before _ready (set_mode now updates synchronously, and some
	# subjects flip mode in their own _ready() before the rig has finished).
	if _camera == null or not is_instance_valid(_camera) or not is_inside_tree():
		return
	var subj_xf := global_transform
	_camera.global_position = subj_xf.origin + subj_xf.basis * third_person_offset
	# Look at the subject's chest/cab height for a nicer framing
	var look := subj_xf.origin + Vector3.UP * 0.8
	_safe_look_at(_camera, look)

## ORBIT: world-space spherical orbit around the subject. Yaw + pitch + distance
## are all under arrow/scroll control while F4 is held.
func _update_orbit_camera() -> void:
	if _camera == null or not is_instance_valid(_camera) or not is_inside_tree():
		return
	var cy := cos(_orbit_yaw)
	var sy := sin(_orbit_yaw)
	var cp := cos(_orbit_pitch)
	var sp := sin(_orbit_pitch)
	# Orbit offset in WORLD coords (positive Y goes up; sp > 0 = camera looks down)
	var offset := Vector3(sy * cp, sp, cy * cp) * _orbit_distance
	var target := global_position + Vector3.UP * 0.8
	_camera.global_position = target + offset
	_safe_look_at(_camera, target)

## look_at that can't produce a NaN/∞ basis: skips when the camera sits ON the target
## (zero direction) and swaps the up-vector when the view is (near-)parallel to UP
## (straight up/down at extreme orbit pitch or zero zoom). A non-finite camera basis
## propagates to any mesh parented to the camera → the renderer's instance_set_transform
## "!is_finite" error. Guarding here kills that at the source.
func _safe_look_at(cam: Camera3D, target: Vector3) -> void:
	if cam == null or not is_instance_valid(cam):
		return
	var dir := target - cam.global_position
	if dir.length() < 0.001:
		return
	var up := Vector3.UP
	if absf(dir.normalized().dot(Vector3.UP)) > 0.999:
		up = Vector3.BACK
	cam.look_at(target, up)

# =============================================================================
# INPUT — F4 hold/tap, scroll zoom, mode cycle
# =============================================================================
## Subject MUST call this from its own _input/_unhandled_input — we don't grab
## the global input handler so the subject keeps control of when this is active
## (e.g. don't capture F4 while the operator is between vehicles).
func handle_input(event: InputEvent) -> bool:
	# F4 press / release
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.keycode == KEY_F4 and not k.echo:
			if k.pressed:
				_f4_held = true
				_f4_acted_this_hold = false
				return true
			else:
				_f4_held = false
				# Tap (no other camera action while held) = cycle mode
				if not _f4_acted_this_hold:
					cycle_mode()
				return true
		# Arrows only consumed while F4 is held + camera is in non-1st mode
		if _f4_held and _mode != Mode.FIRST_PERSON and k.pressed:
			match k.keycode:
				KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN:
					_f4_acted_this_hold = true
					return true
	# Scroll-wheel zoom — only while F4 is held + non-1st mode
	if _f4_held and _mode != Mode.FIRST_PERSON and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_orbit_distance = clampf(_orbit_distance - scroll_zoom_step, orbit_min_dist, orbit_max_dist)
			_f4_acted_this_hold = true
			return true
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_orbit_distance = clampf(_orbit_distance + scroll_zoom_step, orbit_min_dist, orbit_max_dist)
			_f4_acted_this_hold = true
			return true
	return false

## Mouse-look entry point — subject's _unhandled_input forwards
## InputEventMouseMotion.relative here while the cursor is captured.
##
## In FIRST_PERSON: rotates the cab/head camera around the YAWED-then-PITCHED
## axes (real FPS feel: yaw around world up, pitch around the now-yawed right).
##
## In THIRD_PERSON / ORBIT: feeds into orbit_yaw / orbit_pitch directly so the
## mouse and the F4 + arrow keys move the same state.
func handle_mouse_look(rel: Vector2) -> void:
	# Mouse sensitivity respects the gameplay slider in Settings. Look the
	# autoload up via /root rather than by identifier — the identifier doesn't
	# exist when CameraRig is preloaded from a `--script`-mode test (autoloads
	# only register when the full project boots).
	var sens_x := 0.003
	var sens_y := 0.003
	var invert := false
	var invert_cam_x := false
	var invert_cam_y := false
	var sm := _get_settings_node()
	if sm:
		var g: Dictionary = sm.call("gameplay")
		sens_x = float(g.get("mouse_sensitivity_x", 0.003))
		sens_y = float(g.get("mouse_sensitivity_y", 0.003))
		invert = bool(g.get("invert_mouse_y", false))
		invert_cam_x = bool(g.get("invert_cam_x", false))   # #19 outside-vehicle X
		invert_cam_y = bool(g.get("invert_cam_y", false))   # #19 outside-vehicle Y
	var pitch_delta := -rel.y * sens_y
	if invert:
		pitch_delta = -pitch_delta
	var yaw_delta := -rel.x * sens_x
	if _mode == Mode.FIRST_PERSON:
		_cab_yaw   = clampf(_cab_yaw   + yaw_delta,   -CAB_YAW_LIMIT,   CAB_YAW_LIMIT)
		_cab_pitch = clampf(_cab_pitch + pitch_delta, -CAB_PITCH_LIMIT, CAB_PITCH_LIMIT)
		_apply_cab_look()
	else:
		# Outside-vehicle (orbit / 3rd-person) view honours the SEPARATE X/Y invert
		# options (#19). These were only ever wired to arrow-pan — now the MOUSE obeys
		# them too, which is why it "never worked" before.
		var oyaw := yaw_delta
		var opitch := pitch_delta
		if invert_cam_x: oyaw = -oyaw
		if invert_cam_y: opitch = -opitch
		_orbit_yaw   -= oyaw
		_orbit_pitch  = clampf(_orbit_pitch + opitch, PITCH_MIN, PITCH_MAX)

func _get_settings_node() -> Node:
	if get_tree() == null or get_tree().root == null:
		return null
	return get_tree().root.get_node_or_null("SettingsManager")

## Re-applies _cab_yaw / _cab_pitch on top of the cab camera's snapshotted
## INITIAL transform — so the offset is always relative to "looking forward",
## not the previous frame's rotation.
func _apply_cab_look() -> void:
	if _first_person_camera == null or not is_instance_valid(_first_person_camera):
		return
	_first_person_camera.transform = _cab_initial_xf
	_first_person_camera.rotate_y(_cab_yaw)            # yaw around parent (vehicle) Y
	_first_person_camera.rotate_object_local(Vector3.RIGHT, _cab_pitch)

## Reset orbit/zoom (useful when (re-)entering a vehicle or respawning).
func reset() -> void:
	_orbit_yaw      = 0.0
	_orbit_pitch    = -0.25
	_orbit_distance = orbit_default_dist
	_cab_yaw        = 0.0
	_cab_pitch      = 0.0
	if _first_person_camera and is_instance_valid(_first_person_camera):
		_first_person_camera.transform = _cab_initial_xf
	_f4_held = false
	_f4_acted_this_hold = false

## Mode name, for HUD readouts.
func mode_name() -> String:
	match _mode:
		Mode.FIRST_PERSON: return "1st person"
		Mode.THIRD_PERSON: return "3rd-person follow"
		Mode.ORBIT:        return "orbit"
	return "?"
