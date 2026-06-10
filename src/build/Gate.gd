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
## set_drive(-1) for DOWN, and set_drive(0) for STOP. This matches the deadman
## controls on a real overhead-door operator. The leaf itself is just collision
## and visual; you can't interact with it directly.
##
## Built by PlaceableCatalog.build_gate() / the 4-point surface tool, which
## constructs the children (Drum, LeafScaler/Leaf/Col, brackets) before
## _ready runs.

@export var travel_time : float = 4.0   # seconds for a full open or close

var _drive       : int   = 0     # -1 = closing (down), 0 = stop, +1 = opening (up)
var _open_t      : float = 0.0   # 0.0 closed, 1.0 fully open
var _scaler      : Node3D = null
var _opened_min  : float = 0.04  # minimum visible leaf when fully rolled up

# =============================================================================
func _ready() -> void:
	add_to_group("gate")
	_scaler = get_node_or_null("LeafScaler") as Node3D
	# Default state = fully closed. Drive remains 0 until a button is pressed.
	_apply_open_t(0.0)

func _physics_process(delta: float) -> void:
	if _drive == 0:
		return
	var step : float = (delta / maxf(travel_time, 0.1)) * float(_drive)
	_open_t = clampf(_open_t + step, 0.0, 1.0)
	_apply_open_t(_open_t)
	# Auto-stop when we hit the end of travel — real operators trip a limit switch.
	if (_drive > 0 and _open_t >= 1.0) or (_drive < 0 and _open_t <= 0.0):
		_drive = 0

func _apply_open_t(t: float) -> void:
	if _scaler == null:
		return
	var s : float = lerpf(1.0, _opened_min, clampf(t, 0.0, 1.0))
	_scaler.scale = Vector3(1.0, s, 1.0)

# =============================================================================
# PUBLIC — called by GateButtonStation buttons.
# =============================================================================
func set_drive(d: int) -> void:
	_drive = clampi(d, -1, 1)

func is_fully_open() -> bool:
	return _open_t >= 0.999

func is_fully_closed() -> bool:
	return _open_t <= 0.001
