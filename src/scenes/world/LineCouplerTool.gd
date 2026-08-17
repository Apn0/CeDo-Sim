extends StaticBody3D
class_name LineCouplerTool

## Handheld Line Coupler & PLC Wire Tool.
## Allows the operator to point and click machines to wire/link them in LineFlow,
## and couple machines to HMI terminals to configure PLC tabs and scopes.

const tool_id : String = "line_coupler"

const RAY_RANGE        : float = 15.0
const PICKUP_RANGE     : float = 1.8
const ACTION_COOLDOWN  : float = 0.25

var _held_by           : Node3D = null
var _player_near       : bool   = false
var _player_node       : Node   = null
var _last_action_t     : float  = 0.0
var _selected_machine  : Node3D = null
var _hover_target      : Node3D = null

var _status_led        : MeshInstance3D = null

# =============================================================================
func _ready() -> void:
	add_to_group("line_coupler")
	add_to_group("hand_tool")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.15, 0.22, 0.30)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.35

	var cyan_mat := StandardMaterial3D.new()
	cyan_mat.albedo_color = Color(0.18, 0.75, 0.95)
	cyan_mat.emission_enabled = true
	cyan_mat.emission = Color(0.20, 0.85, 1.0)
	cyan_mat.emission_energy_multiplier = 2.0

	var screen_mat := StandardMaterial3D.new()
	screen_mat.albedo_color = Color(0.05, 0.12, 0.18)
	screen_mat.emission_enabled = true
	screen_mat.emission = Color(0.10, 0.40, 0.60)
	screen_mat.emission_energy_multiplier = 1.0

	var dark_grip := StandardMaterial3D.new()
	dark_grip.albedo_color = Color(0.08, 0.08, 0.10)
	dark_grip.roughness = 0.85

	# Main chassis
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.12, 0.22)
	body.mesh = bm
	body.material_override = body_mat
	body.position = Vector3(0.0, 0.04, -0.04)
	add_child(body)

	# LCD Screen on top/back
	var screen := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.06, 0.04, 0.08)
	screen.mesh = sm
	screen.material_override = screen_mat
	screen.position = Vector3(0.0, 0.105, 0.02)
	add_child(screen)

	# Coupling Probe / Antenna at front
	var probe := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.01
	pm.bottom_radius = 0.018
	pm.height = 0.10
	probe.mesh = pm
	probe.material_override = cyan_mat
	probe.rotation_degrees = Vector3(90, 0, 0)
	probe.position = Vector3(0.0, 0.04, -0.19)
	add_child(probe)

	# Status LED
	_status_led = MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.012
	lm.height = 0.024
	_status_led.mesh = lm
	_status_led.material_override = cyan_mat
	_status_led.position = Vector3(0.0, 0.105, -0.06)
	add_child(_status_led)

	# Pistol grip
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new()
	gm.size = Vector3(0.045, 0.15, 0.06)
	grip.mesh = gm
	grip.material_override = dark_grip
	grip.position = Vector3(0.0, -0.07, 0.02)
	add_child(grip)

	# Collision
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.12, 0.25, 0.30)
	col.shape = bx
	add_child(col)

func _build_pickup_trigger() -> void:
	InteractionTriggers.make_pickup_trigger(
		self, PICKUP_RANGE, _on_body_entered, _on_body_exited)

# =============================================================================
# PICKUP / DROP
# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if _held_by != null or body.name != "Player":
		return
	_player_near = true
	_player_node = body

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	_emit_prompt_hide()

func crosshair_prompt(_player: Node3D) -> String:
	return "Take Line Coupler (PLC Wire Tool)" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		_emit_prompt("Hands full — drop something first")
		return
	_held_by = player
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.24, -0.18, -0.45))
	collision_layer = 0
	collision_mask  = 0
	_emit_prompt_hide()

func _drop() -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.6, -0.8)
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask  = 1
	_held_by = null
	_selected_machine = null

# =============================================================================
# INPUT & INTERACTION
# =============================================================================
func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tool_use"):
		_on_primary_action()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_on_secondary_action()
			get_viewport().set_input_as_handled()
			return

func _physics_process(_delta: float) -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	_update_hover_ray()

func _update_hover_ray() -> void:
	var cam : Camera3D = null
	if _held_by:
		cam = _held_by.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		cam = get_viewport().get_camera_3d()
	if cam == null:
		return

	var from := cam.global_position
	var to   := from - cam.global_transform.basis.z * RAY_RANGE
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [get_rid()]
	if _held_by is PhysicsBody3D:
		q.exclude.append((_held_by as PhysicsBody3D).get_rid())

	var hit := space.intersect_ray(q)
	_hover_target = null

	if hit.is_empty():
		return

	var col_node : Node = hit.get("collider")
	var target : Node = _resolve_machine_or_hmi(col_node)
	if target != null and target is Node3D:
		_hover_target = target as Node3D

func _resolve_machine_or_hmi(node: Node) -> Node:
	var n : Node = node
	while n != null and n != get_tree().current_scene:
		if n.is_in_group("hmi") or n.has_meta("hmi_id"):
			return n
		if n.has_meta("placeable_id") or n.is_in_group("placed_object") or n.is_in_group("machine"):
			return n
		n = n.get_parent()
	return null

func _on_primary_action() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_action_t < ACTION_COOLDOWN:
		return
	_last_action_t = now

	if _hover_target == null:
		_banner("[LineCoupler] Aim at a Machine or HMI Terminal to wire/couple.")
		return

	# Case 1: Clicked on an HMI Terminal
	if _hover_target.is_in_group("hmi") or _hover_target.has_meta("hmi_id"):
		_couple_to_hmi(_hover_target)
		return

	# Case 2: Clicked on a Machine
	if _selected_machine == null:
		_selected_machine = _hover_target
		var mname := _get_target_name(_selected_machine)
		_banner("[LineCoupler] Selected: %s\nClick another machine to link flow, or click an HMI to couple." % mname)
	elif _selected_machine == _hover_target:
		_banner("[LineCoupler] Deselected %s." % _get_target_name(_selected_machine))
		_selected_machine = null
	else:
		_link_two_machines(_selected_machine, _hover_target)
		_selected_machine = null

func _link_two_machines(m1: Node3D, m2: Node3D) -> void:
	var name1 := _get_target_name(m1)
	var name2 := _get_target_name(m2)
	
	m1.set_meta("line", "all")
	m2.set_meta("line", "all")
	
	var lf : Node = _find_line_flow()
	if lf and lf.has_method("rebuild"):
		lf.call("rebuild")
		_banner("✓ Linked: %s → %s in LineFlow!" % [name1, name2])
	else:
		_banner("✓ Linked %s and %s" % [name1, name2])

func _couple_to_hmi(hmi_node: Node3D) -> void:
	var hmi_id := ""
	if hmi_node.has_meta("hmi_id"):
		hmi_id = String(hmi_node.get_meta("hmi_id"))
	elif hmi_node.has_meta("placeable_id"):
		hmi_id = String(hmi_node.get_meta("placeable_id"))
	var hmi_title := hmi_id.replace("hmi_", "").replace("_", " ").to_upper()
	if hmi_title == "":
		hmi_title = "HMI Terminal"

	if _selected_machine != null:
		var mname := _get_target_name(_selected_machine)
		_selected_machine.set_meta("hmi_id", hmi_id)
		_selected_machine.set_meta("line", "all")
		var lf : Node = _find_line_flow()
		if lf and lf.has_method("rebuild"):
			lf.call("rebuild")
		_banner("✓ Coupled %s to %s!\nMachine is now active and wired on this PLC tab." % [mname, hmi_title])
		_selected_machine = null
	else:
		# Couple all placed machines
		var machines := get_tree().get_nodes_in_group("placed_object")
		var count := 0
		for m in machines:
			if m is Node3D and m.has_meta("placeable_id"):
				m.set_meta("hmi_id", hmi_id)
				m.set_meta("line", "all")
				count += 1
		var lf : Node = _find_line_flow()
		if lf and lf.has_method("rebuild"):
			lf.call("rebuild")
		_banner("✓ Coupled ALL placed machines (%d) to %s!\nAll machines are now wired to this PLC tab." % [count, hmi_title])

func _on_secondary_action() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_action_t < ACTION_COOLDOWN:
		return
	_last_action_t = now

	# Auto-wire all machines in scene
	var count := 0
	var machines := get_tree().get_nodes_in_group("placed_object")
	for m in machines:
		if m is Node3D and m.has_meta("placeable_id"):
			m.set_meta("line", "all")
			count += 1

	var lf : Node = _find_line_flow()
	if lf and lf.has_method("rebuild"):
		lf.call("rebuild")

	_banner("✓ Auto-Wired all placed machines (%d) to PLC LineFlow!\nAll HMI PLC tabs updated." % count)

func _get_target_name(node: Node) -> String:
	if node == null:
		return "None"
	if node.has_meta("placeable_id"):
		return String(node.get_meta("placeable_id")).replace("_", " ").capitalize()
	if node.has_meta("hmi_id"):
		return String(node.get_meta("hmi_id")).replace("hmi_", "").replace("_", " ").capitalize()
	return node.name

func _find_line_flow() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	var lf : Node = tree.get_first_node_in_group("line_flow")
	if lf == null and tree.current_scene:
		lf = tree.current_scene.find_child("LineFlow", true, false)
	if lf == null and tree.root:
		lf = tree.root.find_child("LineFlow", true, false)
	return lf

func _banner(text: String, is_error: bool = false) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", text, is_error)

func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
