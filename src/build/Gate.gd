extends StaticBody3D
class_name Gate

## Sectional / roller industrial gate.
##
## Looks and moves like the overhead doors you see on a recycling plant's truck
## bays: a horizontal drum sits above the opening, the steel leaf rolls UP into
## the drum to open and DOWN to close. NOT a hinge — this is pure Y-translation
## (modelled as a vertical shrink of the leaf anchored at the top, so the
## "rolled-up" portion disappears into the drum housing).
##
## Driven externally — NOT by pressing E on the leaf itself. A wall-mounted
## 3-button push-button station next to the gate calls set_drive(+1) for UP,
## set_drive(-1) for DOWN, and set_drive(0) for STOP. The leaf itself is just
## collision and visual; you can't interact with it directly.
##
## OPERATOR RULING 2026-09-03, on the real 3A/3B gate: it "is usually open",
## and the station is press-once-and-it-runs, not a held deadman —
##   * TOP button, up arrow    -> press once, the gate runs open and stops itself
##   * CENTRE button           -> stops it mid-travel
##   * BOTTOM button, down arrow, red -> press once, the gate runs shut
## So the gate SPAWNS OPEN (see _ready) and each button latches _drive until a
## limit switch or a STOP press.
##
## Built by PlaceableCatalog.build_gate() / the 4-point surface tool, which
## constructs the children (Drum, LeafScaler/Leaf/Col, brackets) before
## _ready runs.

@export var travel_time : float = 4.0   # seconds for a full open or close

var _drive       : int   = 0     # -1 = closing (down), 0 = stop, +1 = opening (up)
var _open_t      : float = 0.0   # 0.0 closed, 1.0 fully open
var _scaler      : Node3D = null
var _opened_min  : float = 0.04  # minimum visible leaf when fully rolled up
# The physics leaf. A DIRECT child of this StaticBody3D (a shape nested under
# LeafScaler never registers — measured 2026-08-31, shape owners 0) — so
# _apply_open_t must resize it by hand; parent scale cannot do the work.
var _leaf_col    : CollisionShape3D = null
var _leaf_h      : float = 0.0
## Y of the leaf's TOP edge in gate-local space. The leaf rolls UP into the
## drum, so this edge is the one that never moves — every open state is
## "hang `_leaf_h * s` downward from here". build_gate stamps it because the two
## placement paths anchor a gate differently (centre vs base); deriving the box
## from it instead of from the origin is what keeps physics on the visual.
var _leaf_top    : float = 0.0

var _player_near : bool = false

# =============================================================================
func _ready() -> void:
	add_to_group("gate")
	_scaler = get_node_or_null("LeafScaler") as Node3D
	_leaf_col = get_node_or_null("LeafCol") as CollisionShape3D
	if _leaf_col != null and _leaf_col.shape is BoxShape3D:
		_leaf_h = (_leaf_col.shape as BoxShape3D).size.y
	_leaf_top = float(get_meta("leaf_top_y", _leaf_h * 0.5))
	# DEFAULT STATE = FULLY OPEN. Operator ruling 2026-09-03: the real 3A/3B
	# gate "is usually open" and is driven shut deliberately with the button
	# station, not left closed between passes.
	#
	# This is not cosmetic. A closed leaf is a real collider (since 2026-09-03),
	# VehicleRouteGrid shape-casts real colliders, and a gate that spawns closed
	# is a sealed doorway no NPC can open — there is no NPC-presses-a-button
	# path anywhere in the tree. Spawning closed made every indoor->outdoor haul
	# unroutable and silently re-armed test_jam_baseline's skip branch.
	_open_t = 1.0
	_apply_open_t(_open_t)
	_build_interact_trigger()

# #122 — wall-button station is the realistic interface but operators expect
# E-on-gate to also work for the gauntlet walk-through. Add a proximity Area3D
# that catches E and toggles the drive direction (open if closed, close if open,
# stop if mid-travel).
func _build_interact_trigger() -> void:
	var area := Area3D.new()
	area.name = "InteractTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.5, 4.0, 4.0)
	cs.shape = box
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(func(b: Node3D) -> void:
		if b.name == "Player": _player_near = true)
	area.body_exited.connect(func(b: Node3D) -> void:
		if b.name == "Player": _player_near = false)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	var fired : bool = false
	if InputMap.has_action("interact"):
		fired = event.is_action_pressed("interact")
	if (not fired) and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_E:
			fired = true
	if not fired:
		return
	# Toggle: opening / closing reverses, idle picks the opposite of current state.
	if _drive != 0:
		_drive = 0
	elif _open_t < 0.5:
		_drive = 1
	else:
		_drive = -1
	get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if _drive == 0:
		return
	var step : float = (delta / maxf(travel_time, 0.1)) * float(_drive)
	_open_t = clampf(_open_t + step, 0.0, 1.0)
	_apply_open_t(_open_t)
	# Auto-stop when we hit the end of travel — real operators trip a limit switch.
	if (_drive > 0 and _open_t >= 1.0) or (_drive < 0 and _open_t <= 0.0):
		_drive = 0
		# The shared vehicle route grid samples real colliders ONCE and caches.
		# A gate that just finished opening or closing changed exactly that
		# geometry, so without this every vehicle already in the world keeps
		# routing against the leaf's old state for the rest of the session —
		# the same defect BuildMode already guards on placement
		# (BaseVehicle.gd:928-935). Cheap: drops the cache, rebuild stays lazy.
		BaseVehicle.invalidate_route_grid()

func _apply_open_t(t: float) -> void:
	var s : float = lerpf(1.0, _opened_min, clampf(t, 0.0, 1.0))
	if _scaler != null:
		_scaler.scale = Vector3(1.0, s, 1.0)
	# Keep the physics leaf congruent with the visual: both shrink toward the
	# TOP edge of the opening, so the box's centre rises as its height drops.
	if _leaf_col != null and _leaf_h > 0.0 and _leaf_col.shape is BoxShape3D:
		var b := _leaf_col.shape as BoxShape3D
		b.size.y = _leaf_h * s
		# Hang the remaining leaf from the fixed top edge. One formula, both
		# anchor conventions: closed (s = 1) puts the centre half a height below
		# the top, fully open leaves a sliver tucked under the drum.
		_leaf_col.position.y = _leaf_top - _leaf_h * s * 0.5

# =============================================================================
# PUBLIC — called by GateButtonStation buttons.
# =============================================================================
func set_drive(d: int) -> void:
	_drive = clampi(d, -1, 1)

func is_fully_open() -> bool:
	return _open_t >= 0.999

func is_fully_closed() -> bool:
	return _open_t <= 0.001
