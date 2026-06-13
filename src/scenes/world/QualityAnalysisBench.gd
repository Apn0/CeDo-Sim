extends StaticBody3D
## Quality-analysis bench. White lab-style worktop with a PC, a precision scale,
## a sample tray, and a magnifier on a stand — the spot where the QA tech checks
## colour grade / batch MFI / contamination before the granulate ships. Walk up
## and press E to open the quality terminal (a read-out of the latest extruder
## telemetry, sample log, and a "submit sample" button).
##
## Twin of ShiftLeaderDesk.gd: same proximity-trigger + terminal-overlay pattern,
## just a different model + a different terminal class. Catalog id = "qa_bench".

const _TERMINAL_SCRIPT := "res://src/scenes/hud/QualityAnalysisTerminal.gd"

var _player_near : bool = false
var _terminal : CanvasLayer = null

func _ready() -> void:
	add_to_group("qa_bench")
	_build_model()
	_build_collision()
	_build_trigger()

func _build_model() -> void:
	# Material palette — lab whites + dark cabinet + glossy monitor.
	var worktop := StandardMaterial3D.new()
	worktop.albedo_color = Color(0.92, 0.93, 0.92); worktop.roughness = 0.55
	var cabinet := StandardMaterial3D.new()
	cabinet.albedo_color = Color(0.32, 0.34, 0.38); cabinet.metallic = 0.35; cabinet.roughness = 0.45
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.08, 0.08, 0.09); black.roughness = 0.45
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.78, 0.80, 0.82); steel.metallic = 0.55; steel.roughness = 0.30
	var screen := StandardMaterial3D.new()
	screen.albedo_color = Color(0.10, 0.32, 0.46)
	screen.emission_enabled = true
	screen.emission = Color(0.18, 0.62, 0.86)
	screen.emission_energy_multiplier = 1.4
	var led_green := StandardMaterial3D.new()
	led_green.albedo_color = Color(0.18, 0.92, 0.32)
	led_green.emission_enabled = true
	led_green.emission = Color(0.18, 0.92, 0.32)
	led_green.emission_energy_multiplier = 3.0
	var sample := StandardMaterial3D.new()
	sample.albedo_color = Color(0.74, 0.72, 0.66); sample.roughness = 0.80   # off-white plastic flake

	# ── Worktop (2.0 × 0.06 × 0.90) at ~0.88 m high. ──
	_box(Vector3(2.00, 0.06, 0.90), Vector3(0.0, 0.88, 0.0), worktop)
	# Lower cabinet under the worktop — full-width carcass with two drawer faces.
	_box(Vector3(2.00, 0.82, 0.85), Vector3(0.0, 0.41, 0.0), cabinet)
	# Drawer divider line (cosmetic).
	_box(Vector3(1.96, 0.02, 0.86), Vector3(0.0, 0.49, 0.001), black)
	# Two drawer handles.
	for sx in [-0.48, 0.48]:
		_box(Vector3(0.16, 0.04, 0.03), Vector3(sx, 0.60, 0.43), steel)
		_box(Vector3(0.16, 0.04, 0.03), Vector3(sx, 0.30, 0.43), steel)

	# ── PC tower at the LEFT end of the worktop. ──
	_box(Vector3(0.22, 0.42, 0.45), Vector3(-0.78, 1.12, -0.18), black)
	# PC tower power LED — green = ready.
	_box(Vector3(0.04, 0.04, 0.01), Vector3(-0.78, 1.30, 0.075), led_green)

	# ── Monitor on a thin stand, centred. ──
	_box(Vector3(0.08, 0.20, 0.08), Vector3(-0.05, 1.01, -0.22), black)         # neck
	_box(Vector3(0.36, 0.04, 0.22), Vector3(-0.05, 0.93, -0.22), black)         # foot
	_box(Vector3(0.74, 0.46, 0.04), Vector3(-0.05, 1.34, -0.22), black)         # bezel
	_box(Vector3(0.68, 0.40, 0.01), Vector3(-0.05, 1.34, -0.195), screen)       # lit panel
	# Keyboard.
	_box(Vector3(0.48, 0.02, 0.16), Vector3(-0.10, 0.93, 0.16), black)

	# ── Precision scale on the RIGHT side of the worktop. ──
	# White base + glossy black display + steel weighing pan.
	_box(Vector3(0.32, 0.14, 0.32), Vector3(0.55, 0.99, 0.0), worktop)          # scale base
	_box(Vector3(0.22, 0.06, 0.04), Vector3(0.55, 1.04, 0.13), black)           # display
	_box(Vector3(0.26, 0.01, 0.26), Vector3(0.55, 1.07, 0.0), steel)            # pan

	# ── Sample tray (flat dish with film flakes) NEXT to the scale. ──
	_box(Vector3(0.40, 0.04, 0.32), Vector3(0.84, 0.93, 0.0), worktop)          # tray
	_box(Vector3(0.36, 0.025, 0.28), Vector3(0.84, 0.955, 0.0), sample)         # flake heap

	# ── Magnifier on a stand at the front-right corner. Goose-neck shape via
	#     short stacked boxes; light glow at the tip so the QA tech can see it.
	_box(Vector3(0.05, 0.30, 0.05), Vector3(0.85, 1.08, 0.30), steel)            # vertical post
	_box(Vector3(0.18, 0.04, 0.04), Vector3(0.76, 1.21, 0.30), steel)            # arm
	_box(Vector3(0.10, 0.10, 0.02), Vector3(0.66, 1.22, 0.30), screen)           # lens (lit)

## Solid body over the desk volume so the player can't walk through it.
func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	cs.name = "SolidCollision"
	var bx := BoxShape3D.new()
	bx.size = Vector3(2.00, 0.90, 0.90)
	cs.shape = bx
	cs.position = Vector3(0.0, 0.45, 0.0)
	add_child(cs)

func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "BenchTrigger"
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
		bus.emit_signal("interaction_prompt_show", self, "Kwaliteitscontrole (QA-werkbank)")

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
			push_error("[QualityAnalysisBench] %s missing" % _TERMINAL_SCRIPT)
			return
		_terminal = scr.new() as CanvasLayer
		get_tree().root.add_child(_terminal)
		if _terminal.has_method("setup"):
			_terminal.setup(get_node_or_null("/root/EventBus"))
	if _terminal.has_method("toggle"):
		_terminal.toggle()
