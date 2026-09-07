extends Node3D

## FEATURE TESTER — a sandbox off the main menu for tuning a feature's look with
## live dials. Each "feature" (e.g. WaterPipeFeature) declares its tunable params
## and this host auto-generates an HSlider per param, wiring each to the feature's
## set_param() so changes apply in real time. Add more features to FEATURES below
## and they show up in the picker.
##
## Contract a feature must implement (duck-typed):
##   feature_title() -> String
##   build_content()  -> void                # build 3D under itself
##   param_specs()    -> Array[Dictionary]   # {key,label,min,max,step,default}
##   set_param(key, value) -> void

const FEATURES : Array = [
	preload("res://src/scenes/menus/feature_tester/WaterPipeFeature.gd"),
	preload("res://src/scenes/menus/feature_tester/BaleClampDeformationFeature.gd"),
]

var _feature_root : Node3D = null
var _feature      : Node3D = null
var _dials_box    : VBoxContainer = null
var _feature_idx  : int = 0
var _camera       : Camera3D = null
var _camera_yaw   : float = 0.0
var _camera_pitch : float = 0.0
var _camera_dist  : float = 6.0
var _camera_focus : Vector3 = Vector3(1.0, 1.0, 0.0)

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_build_view()
	_build_ui()
	_load_feature(0)
	set_process_input(true)

# ── 3D view: environment + light + camera ─────────────────────────────────────
func _build_view() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.18, 0.20, 0.24)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.52, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	_camera = Camera3D.new()
	add_child(_camera)
	# Focus on pipe mouth area (assembly at x=0, y=1.9, z=-0.6)
	_camera_yaw = deg_to_rad(160.0)
	_camera_pitch = deg_to_rad(15.0)
	_camera_focus = Vector3(0.0, 1.0, -0.6)
	_update_camera_position()

	_feature_root = Node3D.new()
	_feature_root.name = "FeatureRoot"
	add_child(_feature_root)

# ── UI: title, feature picker, dials panel, back button ───────────────────────
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	panel.custom_minimum_size = Vector2(340, 0)
	layer.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.custom_minimum_size = Vector2(300, 0)
	scroll.add_child(col)

	var title := Label.new()
	title.text = "Feature Tester"
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)

	var back := Button.new()
	back.text = "← Back to menu"
	back.mouse_filter = Control.MOUSE_FILTER_STOP
	back.pressed.connect(_on_back)
	col.add_child(back)

	# Feature picker (only one for now, but ready for more).
	if FEATURES.size() > 1:
		var picker := OptionButton.new()
		for i in FEATURES.size():
			var f := FEATURES[i].new() as Node
			picker.add_item(f.call("feature_title") if f.has_method("feature_title") else "Feature %d" % i, i)
			f.free()
		picker.item_selected.connect(_load_feature)
		col.add_child(picker)

	col.add_child(HSeparator.new())

	_dials_box = VBoxContainer.new()
	_dials_box.add_theme_constant_override("separation", 10)
	_dials_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(_dials_box)

# ── Feature lifecycle ─────────────────────────────────────────────────────────
func _load_feature(idx: int) -> void:
	_feature_idx = idx
	if _feature != null and is_instance_valid(_feature):
		_feature.queue_free()
		_feature = null
	for ch in _dials_box.get_children():
		ch.queue_free()

	var script = FEATURES[idx]
	if script == null:
		push_error("[FeatureTester] could not load feature at index %d" % idx)
		return
	_feature = script.new() as Node3D
	_feature_root.add_child(_feature)
	if _feature.has_method("build_content"):
		_feature.call("build_content")

	var specs : Array = _feature.call("param_specs") if _feature.has_method("param_specs") else []
	for spec in specs:
		_add_dial(spec)

## One labelled slider for a param spec. Kept in its own function so each closure
## captures its own `key`/`value_label` (a for-loop lambda would alias them).
func _add_dial(spec: Dictionary) -> void:
	var key : String = String(spec["key"])
	var row := VBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var name_lbl := Label.new()
	name_lbl.text = String(spec.get("label", key))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(name_lbl)
	var value_lbl := Label.new()
	value_lbl.custom_minimum_size = Vector2(56, 0)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(value_lbl)
	row.add_child(header)

	var slider := HSlider.new()
	slider.min_value = float(spec.get("min", 0.0))
	slider.max_value = float(spec.get("max", 1.0))
	slider.step = float(spec.get("step", 0.01))
	slider.value = float(spec.get("default", slider.min_value))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_lbl.text = "%.2f" % slider.value
	slider.value_changed.connect(func(v: float) -> void:
		value_lbl.text = "%.2f" % v
		if _feature != null and is_instance_valid(_feature) and _feature.has_method("set_param"):
			_feature.call("set_param", key, v))
	row.add_child(slider)

	_dials_box.add_child(row)

func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

func _update_camera_position() -> void:
	# Orbital camera: yaw/pitch around focus point at distance
	var pos_x := _camera_focus.x + _camera_dist * cos(_camera_yaw) * cos(_camera_pitch)
	var pos_y := _camera_focus.y + _camera_dist * sin(_camera_pitch)
	var pos_z := _camera_focus.z + _camera_dist * sin(_camera_yaw) * cos(_camera_pitch)
	_camera.position = Vector3(pos_x, pos_y, pos_z)
	_camera.look_at(_camera_focus, Vector3.UP)

func set_camera_active(active: bool) -> void:
	if _camera:
		_camera.current = active

func _unhandled_input(event: InputEvent) -> void:
	# Esc returns to the menu too.
	if event.is_action_pressed("ui_cancel"):
		_on_back()
	# Q/E to adjust distance (zoom)
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			_camera_dist = maxf(_camera_dist - 0.5, 2.0)
			_update_camera_position()
		elif event.keycode == KEY_E:
			_camera_dist = minf(_camera_dist + 0.5, 15.0)
			_update_camera_position()
	# Right-click drag to rotate camera
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		if event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_camera_yaw -= event.relative.x * 0.01
		_camera_pitch += event.relative.y * 0.01
		_camera_pitch = clampf(_camera_pitch, -PI * 0.4, PI * 0.4)
		_update_camera_position()
