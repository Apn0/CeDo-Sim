extends Area3D

## Trigger zone around a vehicle's cab. When the player capsule enters,
## registers the vehicle as the current interactable on OperatorContext.
## Pressing the "interact" action while inside enters the vehicle.
##
## Place as a child of a BaseVehicle scene with a CollisionShape3D sized to
## cover the cab door area.

class_name VehicleEnterArea

# Cached parent vehicle reference (the BaseVehicle this area belongs to).
var _vehicle: Node3D

func _ready() -> void:
	_vehicle = get_parent()
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	# Only react to the player capsule, not NPCs.
	collision_mask = 1     # adjust if you put player on its own layer

func _on_body_entered(body: Node3D) -> void:
	if _vehicle == null:
		return
	if body.name == "Player":
		var op_ctx := _find_operator_context()
		if op_ctx:
			op_ctx.register_interactable(_vehicle)
		# Tell the HUD to show an interaction prompt
		var vtype: String = _vehicle.get("vehicle_type") if "vehicle_type" in _vehicle else "vehicle"
		EventBus.interaction_prompt_show.emit(_vehicle, "Enter %s" % _pretty_type(vtype))

func _on_body_exited(body: Node3D) -> void:
	if body.name == "Player":
		var op_ctx := _find_operator_context()
		if op_ctx:
			op_ctx.unregister_interactable(_vehicle)
		EventBus.interaction_prompt_hide.emit(_vehicle)

# Map internal vehicle_type strings to readable labels
func _pretty_type(t: String) -> String:
	match t:
		"forklift":     return "forklift"
		"bale_clamp":   return "bale clamp"
		"merlo":        return "Merlo"
		"scissor_lift": return "mast lift"   # legacy id — it's a JLG vertical mast lift
		_:              return t.capitalize()

func _find_operator_context() -> OperatorContext:
	# Found via group, not tree position — autoloads occupy the low child indices
	# of root, so get_tree().root.get_child(0) is an autoload, not MainWorld.
	return get_tree().get_first_node_in_group("operator_context") as OperatorContext
