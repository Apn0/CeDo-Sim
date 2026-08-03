extends StaticBody3D
class_name WardrobeLocker

## #154 — In-game wardrobe locker placeable. Press E while looking at it to
## open the character customizer (#153). Loads CharacterCustomizer.gd at
## runtime, parents it under /root, and the customizer handles pause + save.

## #241 — group so crew logic can RESOLVE a locker as a real place to collect
## personal kit from (CrewManager.TOOL_PICKUP_GROUPS). No geometry change.
func _ready() -> void:
	add_to_group("wardrobe_locker")

func crosshair_prompt(_player) -> String:
	return "Open locker (wardrobe) [E]"

func crosshair_interact(_player) -> void:
	var script := load("res://src/scenes/hud/CharacterCustomizer.gd")
	if script == null:
		push_error("[WardrobeLocker] CharacterCustomizer.gd missing")
		return
	# If one is already open (the operator hit two lockers in a row), do nothing.
	if get_tree().root.find_child("CharacterCustomizer", false, false) != null:
		return
	var customizer : Node = script.new()
	customizer.name = "CharacterCustomizer"
	get_tree().root.add_child(customizer)
	if customizer.has_method("open"):
		customizer.call("open")
