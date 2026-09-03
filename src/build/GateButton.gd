extends StaticBody3D
class_name GateButton

## One physical push-button on a GateButtonStation. Three of these sit on the
## station panel, top to bottom: UP (green dome, up arrow), STOP (red mushroom),
## DOWN (red dome, down arrow). Layout and colours per the operator's
## description of the real 3A/3B station, 2026-09-03.
##
## Interaction: the player aims the crosshair at the button and clicks (the
## standard `crosshair_interact` hook used by Door / panels). The button calls
## the linked Gate's set_drive() to either start opening (+1), start closing
## (-1), or halt (0).
##
## NOT a true momentary deadman — a real plant button has to be held. This is
## click-to-drive / click-STOP-to-halt, which is the only sane mapping for a
## first-person crosshair without a held-while-aimed input mode. The visual
## still pops down when clicked so the user gets feedback.

enum Kind { UP, STOP, DOWN }

var kind : int = Kind.STOP
var gate : Node3D = null

var _press_anim : Tween = null
var _visual     : Node3D = null   # the mesh that pops down on press

# =============================================================================
func _ready() -> void:
	add_to_group("gate_button")
	_visual = get_node_or_null("Visual") as Node3D

func crosshair_prompt(_player: Node3D) -> String:
	match kind:
		Kind.UP:   return "[LMB] Gate UP"
		Kind.STOP: return "[LMB] Gate STOP"
		Kind.DOWN: return "[LMB] Gate DOWN"
	return ""

func crosshair_interact(_player: Node3D) -> void:
	if gate == null:
		return
	match kind:
		Kind.UP:
			gate.call("set_drive", 1)
		Kind.STOP:
			gate.call("set_drive", 0)
		Kind.DOWN:
			gate.call("set_drive", -1)
	_play_press_anim()

func _play_press_anim() -> void:
	if _visual == null:
		return
	if _press_anim and _press_anim.is_valid():
		_press_anim.kill()
	var down_pos := Vector3(0.0, 0.0, -0.012)
	var rest_pos := Vector3.ZERO
	_press_anim = create_tween()
	_press_anim.tween_property(_visual, "position", down_pos, 0.06)
	_press_anim.tween_property(_visual, "position", rest_pos, 0.10)
