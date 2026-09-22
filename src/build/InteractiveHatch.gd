extends AnimatableBody3D
class_name InteractiveHatch

## Interactive Hinged Machine Door / Inspection Hatch
## Responds to player crosshair look + [E] interact keypress.
## Swings smoothly open and closed on its hinge axis, revealing machine internals.
##
## ⚠ `sync_to_physics` MUST stay OFF on these. It defaults to TRUE on
## AnimatableBody3D, so `_ready()` below clears it on EVERY hatch rather than
## trusting each construction site to remember — there is one site today
## (PlaceableCatalog._interactive_hatch, which also sets it) and a second one
## that forgot would strand its parts silently.
##
## With it on, Godot drives the body FROM the physics server every tick:
## `global_transform = state.transform`. The server only learns a new transform
## when the body's OWN transform is written — moving an ANCESTOR never notifies
## it. Machines are built at the catalog's local origin and moved into place
## afterwards by the line macro, so the body stayed pinned to the global
## transform it happened to have at build time, which was its intended LOCAL
## offset. Measured 2026-09-16 on line 1: 47 parts across shredder_1,
## vw_trommel, mill, mas_droger and voorraad_silo were floating in a cluster at
## the world origin, e.g. shredder_1's hatch at global (1.76, 3.19, 0.00)
## instead of on a machine standing at (-156.76, 0, 38.98).
##
## These hatches are driven by a Tween on `rotation` (in the process step, not
## _physics_process), which is the case sync_to_physics is NOT for — it exists to
## give engine-animated platforms correct kinematic velocity so they shove
## rigid bodies. A swinging inspection door needs collision, not shove.
## Guarded by test_macro_part_placement.

@export var hatch_name : String = "Inspection Door"
@export var open_angle_deg : float = 105.0
@export var open_time : float = 0.55
@export var hinge_axis : Vector3 = Vector3.UP

var is_open : bool = false
var _moving : bool = false
var _closed_rot : Vector3 = Vector3.ZERO
var _open_rot : Vector3 = Vector3.ZERO
var _tween : Tween = null

func _ready() -> void:
	# Enforced here, not just at the construction site — see the ⚠ note above.
	# A hatch is tween-driven on `rotation`, never engine-animated as a moving
	# platform, so there is no configuration of this class that wants it on.
	sync_to_physics = false
	add_to_group("interactable")
	_closed_rot = rotation
	var target_axis : Vector3 = hinge_axis.normalized()
	_open_rot = _closed_rot + target_axis * deg_to_rad(open_angle_deg)

func crosshair_prompt(_player: Node3D) -> String:
	if _moving:
		return ""
	if is_open:
		return "[E] Close %s" % hatch_name
	return "[E] Open %s" % hatch_name

func crosshair_interact(_player: Node3D) -> void:
	if _moving:
		return
	_moving = true
	is_open = not is_open
	var target_rot : Vector3 = _open_rot if is_open else _closed_rot

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", target_rot, open_time)
	_tween.tween_callback(func():
		_moving = false
	)

	# Sound trigger
	if Engine.has_singleton("AudioManager") or get_tree().root.has_node("AudioManager"):
		var am = get_tree().root.get_node_or_null("AudioManager")
		if am and am.has_method("play_spatial"):
			var sfx := "door_creak" if is_open else "door_slam"
			am.call("play_spatial", sfx, global_position)
