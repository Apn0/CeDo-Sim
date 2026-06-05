extends StaticBody3D
## #3 — the shift-leader's desk + computer in the office (next to the walkie-battery
## bench). Walk up and press E to open the BALE SCAN LOG terminal
## (ShiftLeaderTerminal), which reads ScanLog: the running record of every bale the
## barcode gun has actually scanned this shift (which bale, when, by whom, which line).

const _TERMINAL_SCRIPT := "res://src/scenes/hud/ShiftLeaderTerminal.gd"

var _player_near : bool = false
var _terminal : CanvasLayer = null

func _ready() -> void:
	add_to_group("shift_leader_desk")
	_build_model()
	_build_collision()
	_build_trigger()

func _build_model() -> void:
	var wood := StandardMaterial3D.new();  wood.albedo_color = Color(0.30, 0.22, 0.16); wood.roughness = 0.7
	var steel := StandardMaterial3D.new(); steel.albedo_color = Color(0.20, 0.21, 0.23); steel.metallic = 0.55; steel.roughness = 0.4
	var black := StandardMaterial3D.new(); black.albedo_color = Color(0.06, 0.06, 0.07); black.roughness = 0.5
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.10, 0.42, 0.30)
	screen.emission_enabled = true
	screen.emission = Color(0.14, 0.58, 0.38)
	screen.emission_energy_multiplier = 1.4

	_box(Vector3(1.60, 0.06, 0.80), Vector3(0.0, 0.74, 0.0), wood)        # desk top
	_box(Vector3(0.05, 0.74, 0.78), Vector3(-0.76, 0.37, 0.0), steel)     # left side panel
	_box(Vector3(0.05, 0.74, 0.78), Vector3( 0.76, 0.37, 0.0), steel)     # right side panel
	_box(Vector3(0.22, 0.46, 0.45), Vector3(0.55, 0.23, -0.10), black)    # PC tower under desk
	_box(Vector3(0.08, 0.18, 0.08), Vector3(0.0, 0.86, -0.20), black)     # monitor neck
	_box(Vector3(0.30, 0.04, 0.18), Vector3(0.0, 0.78, -0.20), black)     # monitor foot
	_box(Vector3(0.62, 0.40, 0.04), Vector3(0.0, 1.12, -0.22), black)     # monitor bezel
	_box(Vector3(0.56, 0.34, 0.01), Vector3(0.0, 1.12, -0.195), screen)   # lit screen (faces +Z, toward operator)
	_box(Vector3(0.44, 0.02, 0.16), Vector3(0.0, 0.78, 0.18), black)      # keyboard

func _box(size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	add_child(mi)

## #10 — a solid body over the desk volume so the player can't walk through it.
func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	cs.name = "SolidCollision"
	var bx := BoxShape3D.new()
	bx.size = Vector3(1.60, 0.80, 0.85)
	cs.shape = bx
	cs.position = Vector3(0.0, 0.40, 0.0)
	add_child(cs)

func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "DeskTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(2.6, 2.4, 2.6)
	cs.shape = bx
	cs.position = Vector3(0.0, 1.0, 0.7)   # bias toward the operator side (+Z)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Open scanlog (bedrijfsleider-PC)")

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near:
		return
	if event.is_action_pressed("interact"):
		_open_terminal()
		get_viewport().set_input_as_handled()

func _open_terminal() -> void:
	if _terminal == null or not is_instance_valid(_terminal):
		var scr := load(_TERMINAL_SCRIPT)
		if scr == null:
			push_error("[ShiftLeaderDesk] %s missing" % _TERMINAL_SCRIPT)
			return
		_terminal = scr.new() as CanvasLayer
		get_tree().root.add_child(_terminal)
		# We're inside the active scene, so we CAN resolve the autoloads here and
		# hand them to the terminal (which lives under root, where it can't).
		if _terminal.has_method("setup"):
			_terminal.setup(get_node_or_null("/root/EventBus"), get_node_or_null("/root/ScanLog"))
	if _terminal.has_method("toggle"):
		_terminal.toggle()
