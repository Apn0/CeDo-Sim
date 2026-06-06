extends StaticBody3D
class_name Hmi

## An interactive HMI panel — stand-mounted or wall-mounted.
##
## A proximity Area3D fires the standard interaction prompt when the player
## walks near. Pressing the interact action (E) opens HmiOverlay.tscn, a
## fullscreen panel where the operator can:
##   - read the LineFlow throughput / waste / granulaat counters
##   - START / STOP the feed (drives LineFlow.feed_enabled)
##   - (placeholder) set a target rate, see machine count
##
## Built by PlaceableCatalog.build_node() when category == "Control"; that
## function attaches this script to the body and lets _ready() do the rest.

const _OVERLAY_PATH := "res://src/scenes/hud/HmiOverlay.tscn"

# One overlay instance is shared between every HMI in the world — opens for
# whichever panel the player most recently interacted with.
static var _overlay : CanvasLayer = null

var _player_near : bool = false
var _label       : String = "HMI"

func _ready() -> void:
	add_to_group("hmi")
	if has_meta("placeable_id"):
		_label = String(get_meta("placeable_id")).capitalize().replace("_", " ")
	_build_trigger()

func _build_trigger() -> void:
	# Proximity zone around the HMI head — the player gets a prompt when in
	# range and can press the interact key to open the panel.
	var area := Area3D.new()
	area.name = "HmiTrigger"
	area.collision_mask = 1
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.0, 2.4, 2.0)
	cs.shape = box
	cs.position = Vector3(0.0, 1.0, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	EventBus.interaction_prompt_hide.emit(self)

func _unhandled_input(event: InputEvent) -> void:
	# Open is driven by PlayerController's crosshair interaction ray.
	return

func crosshair_prompt(_player: Node3D) -> String:
	return "Open %s" % _label if _player_near else ""

func crosshair_interact(_player: Node3D) -> void:
	if _player_near:
		_open_overlay()

## Lazy-loads the shared overlay on first use, then shows it.
func _open_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		var scene := load(_OVERLAY_PATH) as PackedScene
		if scene == null:
			push_error("[Hmi] %s missing" % _OVERLAY_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		get_tree().root.add_child(_overlay)
	if _overlay.has_method("open_for"):
		_overlay.open_for(_label)
	else:
		_overlay.visible = true
	# Free the mouse so the player can click the overlay buttons.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
