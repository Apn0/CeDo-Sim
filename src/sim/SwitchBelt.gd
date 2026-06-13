extends Node
class_name SwitchBelt

## #137 — drives the linear jog of the conveyor-12 switch belt. The belt's
## DECK assembly (pulleys + skin + rails, parented under a `Deck` child node
## by PlaceableCatalog._m_switch_belt) slides along its conveying axis from
## -1.5 m (100 % to first downstream, typically VSS_3A) to +1.5 m (100 % to
## the second downstream, typically VSS_3B), with smooth blending in between.
##
## The TARGET position is computed by LineFlow each tick from the two
## downstream buffers (emptier silo pulls the jog toward itself); this script
## just smoothly moves the deck toward that target at the operator-specified
## 10 cm/s. Setting it up as a Node (not Node3D) child of the StaticBody3D
## keeps it physics-agnostic — the deck is a sibling, not a parent.

const JOG_HALF_RANGE_M : float = 1.5    # operator spec: ±1.5 m travel
const JOG_SPEED_M_S    : float = 0.10   # 10 cm/s linear move

# Public state — LineFlow reads jog_x (lagged position) for the SHARE calc and
# writes jog_target (-1.5..+1.5) every tick from the downstream buffers.
var jog_x      : float = 0.0
var jog_target : float = 0.0

var _deck     : Node3D = null   # cached deck root child of the body
var _deck_home: Vector3 = Vector3.ZERO

## Attach this controller to `body` (the switch belt's StaticBody3D). Returns
## the existing controller if `body` already has one — so re-registering is
## idempotent. The Deck child is found by name and its initial transform
## remembered as the "home" pose (jog_x == 0).
static func attach_to(body: Node3D) -> SwitchBelt:
	if body == null:
		return null
	var existing := body.get_node_or_null("_SwitchBeltCtrl") as SwitchBelt
	if existing != null:
		return existing
	var ctrl := SwitchBelt.new()
	ctrl.name = "_SwitchBeltCtrl"
	body.add_child(ctrl)
	# Deck is under Model/Deck (Model is what _build_model populates; the catalog
	# builder for switch_belt parents the moving parts under that "Deck" Node3D).
	var deck : Node3D = body.get_node_or_null("Model/Deck") as Node3D
	if deck == null:
		# Older builds may not have the named child; fall back to a search so
		# the script still works on saves baked before this patch.
		deck = body.find_child("Deck", true, false) as Node3D
	if deck != null:
		ctrl._deck = deck
		ctrl._deck_home = deck.position
	return ctrl

## Clamp + record the new target. Called each tick from LineFlow with the
## buffer-aware share converted to a jog position (see _jog_target_for_split).
func set_jog_target(t: float) -> void:
	jog_target = clampf(t, -JOG_HALF_RANGE_M, JOG_HALF_RANGE_M)

## Convert a desired "share to first downstream" (0..1) to the matching jog
## position. share = 1 → all to first → jog at -1.5 m; share = 0 → all to
## second → jog at +1.5 m; share = 0.5 → centred. Static helper because the
## LineFlow tick computes the share before it even resolves the controller.
static func jog_target_for_share(share_to_first: float) -> float:
	var s : float = clampf(share_to_first, 0.0, 1.0)
	return JOG_HALF_RANGE_M - 2.0 * JOG_HALF_RANGE_M * s

## Convert the CURRENT jog position back to the actual share going to the
## first downstream this frame. LineFlow reads this for the material split so
## the visible deck position drives the actual flow split (laggy by design —
## the deck has to physically move before the routing follows).
func share_to_first_from_jog() -> float:
	return clampf(0.5 - jog_x / (2.0 * JOG_HALF_RANGE_M), 0.0, 1.0)

func _physics_process(delta: float) -> void:
	# Move toward target at the fixed jog speed. The clamp prevents overshoot
	# when target and position are within one step of each other.
	var diff : float = jog_target - jog_x
	if absf(diff) <= 1e-4:
		return
	var step : float = JOG_SPEED_M_S * delta
	if absf(diff) <= step:
		jog_x = jog_target
	else:
		jog_x += step if diff > 0.0 else -step
	# Slide the deck along its CONVEYING axis. The deck mesh is laid in the
	# body's local Z direction (the long side of the catalog size, 4.0 m), so
	# jog_x maps to local Z displacement.
	if _deck != null and is_instance_valid(_deck):
		_deck.position = _deck_home + Vector3(0.0, 0.0, jog_x)
