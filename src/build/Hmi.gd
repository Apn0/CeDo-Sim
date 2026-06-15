extends StaticBody3D
class_name Hmi

## An interactive HMI panel — stand-mounted or wall-mounted.
##
## A proximity Area3D fires the standard interaction prompt when the player
## walks near. Pressing the interact action (E) opens HmiOverlay.tscn, a
## fullscreen panel where the operator can read/control the SCOPED subset of
## the plant this physical panel governs (#165).
##
## Each placed HMI carries an `hmi_id` meta (set by PlaceableCatalog.build_node
## from the catalog entry, default "generic" for the legacy `hmi_panel` /
## `hmi_wall` ids). On interact, we look up the scope in HmiScopes.gd and pass
## it to HmiOverlay.open_for(scope, label) — the overlay then filters its
## SECTIONS / STAGES / MACHINES list / HANDBEDIENING rows / START-STOP gates by
## that scope, so this physical panel only ever shows + controls its assigned
## machines.
##
## Built by PlaceableCatalog.build_node() when category == "Control"; that
## function attaches this script to the body and lets _ready() do the rest.

const _OVERLAY_PATH := "res://src/scenes/hud/HmiOverlay.tscn"
const _SCOPES := preload("res://src/build/HmiScopes.gd")

# One overlay instance is shared between every HMI in the world — opens for
# whichever panel the player most recently interacted with. The overlay is
# re-scoped on every open_for(), so opening HMI-A then HMI-B never leaks A's
# selection or machine list into B.
static var _overlay : CanvasLayer = null

var _player_near : bool = false
var _label       : String = "HMI"
var _hmi_id      : String = _SCOPES.GENERIC_ID

func _ready() -> void:
	add_to_group("hmi")
	# Resolve which scope this physical panel owns. `hmi_id` meta wins; legacy
	# `hmi_panel`/`hmi_wall` placeables fall back to the generic see-all scope.
	_hmi_id = _SCOPES.resolve_hmi_id(self)
	var scope := _SCOPES.get_scope(_hmi_id)
	_label = String(scope.get("label", "HMI"))
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

func crosshair_prompt(_player: Node3D) -> String:
	return "Open %s" % _label if _player_near else ""

func crosshair_interact(_player: Node3D) -> void:
	if _player_near:
		_open_overlay()

## Lazy-loads the shared overlay on first use, then opens it scoped to THIS
## panel. Re-opening on a different HMI always re-applies its scope, so the
## list/sections never carry over from the previous panel.
func _open_overlay() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		var scene := load(_OVERLAY_PATH) as PackedScene
		if scene == null:
			push_error("[Hmi] %s missing" % _OVERLAY_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		get_tree().root.add_child(_overlay)
	var scope := _SCOPES.get_scope(_hmi_id)
	if _overlay.has_method("open_for"):
		# Pass BOTH the scope and the label so the overlay can filter its
		# screens. The overlay tolerates a missing scope arg (back-compat).
		_overlay.open_for(_label, scope)
	else:
		_overlay.visible = true
	# Free the mouse so the player can click the overlay buttons.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
