extends StaticBody3D
class_name JerryCan

## A jerry can / gas canister sitting in the world. Walk up, press E with a leaf
## blower (or any other fuel-burning held tool with a refuel() method) in your
## inventory, and EVERY held tool that takes fuel is topped up to full.
##
## Per the operator's spec the can itself has INFINITE fuel — you only refuel
## the tools, not the can. That's the whole point: place a can somewhere and
## never have to worry about supply, only about making the trip to fill up.
##
## Placed from the build menu (Tools → "Jerry can (fuel)"). Same proximity-prompt
## pattern as the battery bench / shift-leader desk.

const tool_id : String = "jerrycan"

var _player_near : bool = false
var _player_node : Node = null

# =============================================================================
func _ready() -> void:
	add_to_group("jerrycan")
	_build_visual()
	_build_collision()
	_build_trigger()

## Boxy red metal jerry can — corrugated sides, two top handles, screw cap,
## central pour spout. Sized ~ 30 × 35 × 17 cm to match a real 20 L can.
func _build_visual() -> void:
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.16, 0.14); red.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.08, 0.08, 0.10); dark.roughness = 0.85
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.76, 0.62, 0.20); brass.metallic = 0.85; brass.roughness = 0.30
	# Main body
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.30, 0.35, 0.17)
	body.mesh = bm; body.material_override = red
	body.position = Vector3(0, 0.175, 0)
	add_child(body)
	# Corrugated side ribs — two on each long face.
	for sx in [-1.0, 1.0]:
		for sy in [-0.05, 0.05]:
			var rib := MeshInstance3D.new()
			var rm := BoxMesh.new(); rm.size = Vector3(0.005, 0.30, 0.16)
			rib.mesh = rm; rib.material_override = red
			rib.position = Vector3(sx * 0.155, 0.175 + sy * 0.10, 0.0)
			add_child(rib)
	# Top handles — twin loops on the cap face.
	for sx in [-0.06, 0.06]:
		var h := MeshInstance3D.new()
		var hm := BoxMesh.new(); hm.size = Vector3(0.04, 0.025, 0.10)
		h.mesh = hm; h.material_override = dark
		h.position = Vector3(sx, 0.365, 0.0)
		add_child(h)
	# Pour spout — short cylinder + brass cap.
	var spout := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.018; sm.bottom_radius = 0.022; sm.height = 0.06
	sm.radial_segments = 14
	spout.mesh = sm
	spout.material_override = dark
	spout.position = Vector3(0.0, 0.385, 0.06)
	add_child(spout)
	var cap := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.022; cm.bottom_radius = 0.022; cm.height = 0.02
	cm.radial_segments = 14
	cap.mesh = cm
	cap.material_override = brass
	cap.position = Vector3(0.0, 0.420, 0.06)
	add_child(cap)
	# "FUEL" placard on the long face.
	var placard := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.20, 0.06, 0.005)
	placard.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.95, 0.85, 0.10); pmat.roughness = 0.7
	placard.material_override = pmat
	placard.position = Vector3(0, 0.20, 0.087)
	add_child(placard)

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.30, 0.40, 0.17)
	col.shape = bx
	col.position = Vector3(0, 0.20, 0)
	add_child(col)

func _build_trigger() -> void:
	InteractionTriggers.make_pickup_trigger(
		self, 1.5, _on_body_entered, _on_body_exited,
		"JerryCanTrigger", 1, Vector3(0.0, 0.3, 0.0))

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	_player_node = body
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Bijtanken (E)")

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	if not event.is_action_pressed("interact"):
		return
	if _refuel_player_tools() > 0:
		get_viewport().set_input_as_handled()

## Top up every fuel-burning tool the player is carrying (in the Inventory
## autoload's slots). Returns how many tools were actually refuelled, so the
## caller can decide whether to swallow the E press.
func _refuel_player_tools() -> int:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null:
		return 0
	var n : int = int(inv.NUM_SLOTS) if "NUM_SLOTS" in inv else 4
	var refilled := 0
	for i in n:
		var t = inv.slots[i] if i < (inv.slots as Array).size() else null
		if t != null and is_instance_valid(t) and t.has_method("refuel"):
			t.call("refuel")   # default = top off
			refilled += 1
	return refilled
