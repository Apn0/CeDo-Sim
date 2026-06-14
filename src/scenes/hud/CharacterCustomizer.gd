extends CanvasLayer
class_name CharacterCustomizer

## #153 — GTA-style wardrobe / character customizer.
##
## Layout: half-screen preview viewport on the left showing the player's
## Humanoid rotating on a turntable (mouse-drag to rotate manually); right
## side has dropdowns / colour pickers for shirt, pants, hair, beard, cap,
## and PPE class. SAVE button persists to GameState.player_appearance and
## rebuilds the player's body so the world view matches when you close.
## ESC / RIGHT-CLICK closes without saving.
##
## Entered from:
##   (a) Main menu — "Customise character" button (calls open(preview_only=true))
##   (b) In-game wardrobe locker (#154) — crosshair_interact opens it overlaid
##       on the world (mouse mode visible, game still paused).
##
## Persistence (#186): per-character wardrobe keyed by display name. Each
## character carries TWO outfits — on_duty (with PPE) + off_duty (personal
## clothes) — and MainWorld picks the active one from ShiftClock.shift_active.
##   GameState.player_name      : String                — "Arno" by default
##   GameState.player_wardrobes : Dictionary[name → {on_duty, off_duty}]
##   GameState.player_appearance: Dictionary            — flat dict reflecting
##       the currently-active outfit; kept in sync with the wardrobe so legacy
##       readers (Humanoid.build) still work without re-querying the wardrobe.
##
## Appearance dict shape (one outfit slot):
##   shirt_color : Color (or {r,g,b} dict on disk after JSON roundtrip) — TINT
##   pants_color : Color
##   hair        : "bald" / "buzz" / "short" / "mid" / "long" / "ponytail" / "mullet"
##   beard       : "none" / "thin" (stubble dots) / "thick" / "full"
##                 / "mustache" / "goatee"
##   cap         : bool  — layered OVER the hair (no longer replaces it)
##   ppe         : "hi_vis" / "operator" / "none" — additive vest overlay

signal saved(appearance: Dictionary)
signal cancelled()

const HUMANOID_SCRIPT_PATH := "res://src/scenes/world/Humanoid.gd"

# UI roots
var _root           : Control = null
var _preview_vp     : SubViewport = null
var _preview_world  : Node3D = null
var _preview_body   : Node3D = null
var _preview_camera : Camera3D = null
var _preview_turntable : Node3D = null

# Edits (live preview), committed to GameState on save. `_appearance` is the
# FLAT dict for whichever {character, wear_state} slot is currently being
# edited. `_all_outfits` holds the full structure so flipping the wear_state
# selector doesn't lose the other slot's edits.
var _appearance : Dictionary = {}

# Multi-character: which character is being edited
var _character_id : String = "player"
# #186 — for the player slot we now keep TWO outfits per character (on_duty +
# off_duty). NPCs keep ONE outfit (their shift outfit) since the off-shift
# story for NPCs isn't surfaced yet. Shape:
#   _all_outfits["player"] = { "on_duty": {...}, "off_duty": {...} }
#   _all_outfits["romain"] = { "on_duty": {...} }     # NPC, one slot
var _all_outfits : Dictionary = {}
# Currently-selected wear_state for the active character. Defaults to on_duty.
var _wear_state  : String = "on_duty"

# Mouse drag for the preview rotation
var _drag_active : bool = false
var _drag_last_x : float = 0.0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS    # works while the game is paused
	layer = 100                                # above HUD
	_build_ui()
	_load_initial_appearance()
	_rebuild_preview_body()

# ── Public API ───────────────────────────────────────────────────────────────
## Open the customizer overlaid on whatever is on screen. Captures the mouse
## visible + pauses the tree so the player can edit cleanly.
var _prev_mouse_mode : int = Input.MOUSE_MODE_VISIBLE
var _was_paused : bool = false

func open() -> void:
	if _root:
		_root.visible = true
	_prev_mouse_mode = Input.mouse_mode
	_was_paused = get_tree().paused
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	get_tree().paused = true

func close(commit: bool) -> void:
	if commit:
		_commit_to_gamestate()
		saved.emit(_appearance.duplicate())
	else:
		cancelled.emit()
	get_tree().paused = _was_paused
	Input.mouse_mode = _prev_mouse_mode
	queue_free()

# ── UI ────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	_root = Control.new()
	_root.name = "CustomizerRoot"
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	# Dimmed full-screen backdrop so the underlying world reads as background.
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.05, 0.06, 0.92)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_PASS
	_root.add_child(dim)
	# Left: 3D preview viewport.
	var preview_container := SubViewportContainer.new()
	preview_container.name = "PreviewContainer"
	preview_container.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	preview_container.offset_left = 32
	preview_container.offset_top = 32
	preview_container.offset_right = 700
	preview_container.offset_bottom = -32
	preview_container.stretch = true
	preview_container.mouse_filter = Control.MOUSE_FILTER_STOP
	preview_container.gui_input.connect(_on_preview_gui_input)
	_root.add_child(preview_container)
	_preview_vp = SubViewport.new()
	_preview_vp.size = Vector2i(668, 720)
	_preview_vp.handle_input_locally = false
	_preview_vp.disable_3d = false
	_preview_vp.transparent_bg = true
	preview_container.add_child(_preview_vp)
	_build_preview_world()
	# Right: form panel.
	var form := VBoxContainer.new()
	form.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	form.offset_left = -460
	form.offset_top = 60
	form.offset_right = -32
	form.offset_bottom = -32
	form.add_theme_constant_override("separation", 14)
	_root.add_child(form)
	_build_form(form)

func _build_preview_world() -> void:
	_preview_world = Node3D.new()
	_preview_world.name = "PreviewWorld"
	_preview_vp.add_child(_preview_world)
	# Sun + ambient.
	var light := DirectionalLight3D.new()
	light.rotation = Vector3(-deg_to_rad(45.0), deg_to_rad(35.0), 0.0)
	light.light_energy = 1.2
	_preview_world.add_child(light)
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.08, 0.10, 0.13)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.65, 0.66, 0.70)
	environment.ambient_light_energy = 0.5
	env.environment = environment
	_preview_world.add_child(env)
	# Turntable that holds the body — _process spins it.
	_preview_turntable = Node3D.new()
	_preview_turntable.name = "Turntable"
	_preview_world.add_child(_preview_turntable)
	# Floor disc — readable as the locker-room floor.
	var floor_mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.8
	cm.bottom_radius = 0.8
	cm.height = 0.02
	floor_mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.22, 0.24)
	mat.roughness = 0.9
	floor_mi.material_override = mat
	floor_mi.position = Vector3(0.0, 0.0, 0.0)
	_preview_turntable.add_child(floor_mi)
	# Camera framing the body.
	_preview_camera = Camera3D.new()
	_preview_camera.position = Vector3(0.0, 1.0, 2.6)
	_preview_camera.fov = 38.0
	_preview_camera.current = true
	_preview_world.add_child(_preview_camera)
	_preview_camera.look_at(Vector3(0.0, 0.9, 0.0), Vector3.UP)

var _form_container : VBoxContainer = null

func _build_form(parent: VBoxContainer) -> void:
	_form_container = parent
	_populate_form()

func _rebuild_form() -> void:
	if _form_container == null:
		return
	for c in _form_container.get_children():
		c.queue_free()
	_populate_form()

func _populate_form() -> void:
	var parent := _form_container
	var title := Label.new()
	title.text = "Wardrobe"
	title.add_theme_font_size_override("font_size", 32)
	parent.add_child(title)
	# Character selector — always available so all NPCs can be customised.
	# #186 — player display name comes from GameState.player_name (default "Arno")
	# instead of the hardcoded "Player" string. Real operators have real names.
	var gs : Node = get_node_or_null("/root/GameState")
	var player_display_name : String = "Arno"
	if gs and "player_name" in gs:
		var pn = gs.get("player_name")
		if pn is String and String(pn) != "":
			player_display_name = String(pn)
	var char_ids : Array = ["player"]
	var char_labels : Array = [player_display_name]
	var npc_data : Dictionary = {}
	var mw_script = load("res://src/scenes/world/MainWorld.gd")
	if mw_script and "NPC_DATA" in mw_script:
		npc_data = mw_script.NPC_DATA
	elif get_tree().current_scene and "NPC_DATA" in get_tree().current_scene:
		npc_data = get_tree().current_scene.get("NPC_DATA")
	for npc_id in npc_data:
		char_ids.append(npc_id)
		char_labels.append(String(npc_data[npc_id].get("name", npc_id)).capitalize())
	if char_ids.size() > 1:
		var char_row := HBoxContainer.new()
		char_row.add_theme_constant_override("separation", 12)
		var clbl := Label.new()
		clbl.text = "Character"
		clbl.custom_minimum_size = Vector2(140, 0)
		char_row.add_child(clbl)
		var cmenu := OptionButton.new()
		for i in char_ids.size():
			cmenu.add_item(String(char_labels[i]), i)
		for i in char_ids.size():
			if String(char_ids[i]) == _character_id:
				cmenu.select(i)
				break
		var ids_copy := char_ids.duplicate()
		cmenu.item_selected.connect(func(idx): _switch_character(String(ids_copy[idx])))
		char_row.add_child(cmenu)
		parent.add_child(char_row)
	# #186 — Player NAME field (only when the active character is the player).
	# The node name in MainWorld stays "Player" (other systems look it up by that
	# string), but this drives the display-name meta + every UI that shows it.
	if _character_id == "player":
		var name_row := HBoxContainer.new()
		name_row.add_theme_constant_override("separation", 12)
		var nlbl := Label.new()
		nlbl.text = "Name"
		nlbl.custom_minimum_size = Vector2(140, 0)
		name_row.add_child(nlbl)
		var name_edit := LineEdit.new()
		name_edit.text = player_display_name
		name_edit.placeholder_text = "Arno"
		name_edit.custom_minimum_size = Vector2(220, 36)
		name_edit.text_changed.connect(func(t):
			# Stash on the appearance dict so _commit_to_gamestate writes it.
			_appearance["_player_name"] = String(t) if String(t).strip_edges() != "" else "Arno"
		)
		name_row.add_child(name_edit)
		parent.add_child(name_row)
	# #186 — wear_state toggle (on_duty / off_duty). The customizer edits one
	# outfit slot at a time; flipping this switches the form binding without
	# closing/reopening. MainWorld picks the active slot from shift_active.
	var ws_row := HBoxContainer.new()
	ws_row.add_theme_constant_override("separation", 12)
	var wslbl := Label.new()
	wslbl.text = "Editing"
	wslbl.custom_minimum_size = Vector2(140, 0)
	ws_row.add_child(wslbl)
	var ws_menu := OptionButton.new()
	ws_menu.add_item("On-duty (PPE)", 0)
	ws_menu.add_item("Off-duty (personal)", 1)
	ws_menu.select(0 if _wear_state == "on_duty" else 1)
	ws_menu.item_selected.connect(func(idx): _switch_wear_state("on_duty" if idx == 0 else "off_duty"))
	ws_row.add_child(ws_menu)
	parent.add_child(ws_row)
	# Skin colour
	parent.add_child(_make_color_row("Skin", "skin_color",
		_appearance.get("skin_color", Color(0.94, 0.78, 0.66))))
	# Hair colour
	parent.add_child(_make_color_row("Hair colour", "hair_color",
		_appearance.get("hair_color", Color(0.09, 0.07, 0.06))))
	# Shirt type
	parent.add_child(_make_option_row("Top", "shirt_type",
		["t_shirt", "sweatshirt", "hi_vis_coat"],
		_appearance.get("shirt_type", "t_shirt")))
	# Shirt colour
	parent.add_child(_make_color_row("Shirt", "shirt_color",
		_appearance.get("shirt_color", Color(0.96, 0.45, 0.12))))
	# Pants colour
	parent.add_child(_make_color_row("Pants", "pants_color",
		_appearance.get("pants_color", Color(0.10, 0.15, 0.32))))
	# Footwear
	parent.add_child(_make_option_row("Footwear", "footwear",
		["shoes", "work_boots"],
		_appearance.get("footwear", "work_boots")))
	# Hair style — #186 expanded list: bald / buzz / short / mid / long /
	# ponytail / mullet. Order matches the visual length/shortness scale so the
	# operator can scan it without re-reading every option.
	parent.add_child(_make_option_row("Hair style", "hair",
		["bald", "buzz", "short", "mid", "long", "ponytail", "mullet"],
		_appearance.get("hair", "short")))
	# Beard
	parent.add_child(_make_option_row("Beard", "beard",
		["none", "thin", "thick", "full", "mustache", "goatee"],
		_appearance.get("beard", "none")))
	# Cap (#186 — now LAYERED over hair instead of replacing it)
	parent.add_child(_make_check_row("Wear cap", "cap",
		bool(_appearance.get("cap", false))))
	# PPE class — #186: dropdown now actually drives clothing. "hi_vis" adds a
	# yellow vest, "operator" adds an orange vest + hardhat, "none" leaves
	# personal clothes alone. Independent of shirt_type — both stack.
	parent.add_child(_make_option_row("PPE class", "ppe",
		["hi_vis", "operator", "none"], _appearance.get("ppe", "hi_vis")))
	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	parent.add_child(spacer)
	# Buttons row
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 18)
	parent.add_child(buttons)
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(140, 44)
	save_btn.pressed.connect(func(): close(true))
	buttons.add_child(save_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(140, 44)
	cancel_btn.pressed.connect(func(): close(false))
	buttons.add_child(cancel_btn)
	# Hint
	var hint := Label.new()
	hint.text = "Mouse-drag preview to rotate.  ESC to cancel."
	hint.modulate = Color(0.7, 0.7, 0.7)
	parent.add_child(hint)

func _make_color_row(label_text: String, key: String, initial: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	row.add_child(lbl)
	var picker := ColorPickerButton.new()
	picker.color = initial
	picker.custom_minimum_size = Vector2(160, 36)
	picker.color_changed.connect(func(c): _set_appearance(key, c))
	row.add_child(picker)
	return row

func _make_option_row(label_text: String, key: String, options: Array, initial: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	row.add_child(lbl)
	var menu := OptionButton.new()
	for i in options.size():
		menu.add_item(String(options[i]).capitalize(), i)
	for i in options.size():
		if String(options[i]) == initial:
			menu.select(i)
			break
	menu.item_selected.connect(func(idx): _set_appearance(key, String(options[idx])))
	row.add_child(menu)
	return row

func _make_check_row(label_text: String, key: String, initial: bool) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(140, 0)
	row.add_child(lbl)
	var cb := CheckBox.new()
	cb.button_pressed = initial
	cb.toggled.connect(func(v): _set_appearance(key, v))
	row.add_child(cb)
	return row

# ── State management ────────────────────────────────────────────────────────
func _load_initial_appearance() -> void:
	var gs : Node = get_node_or_null("/root/GameState")
	# Load player appearance
	if gs and "player_appearance" in gs:
		var stored = gs.get("player_appearance")
		if stored is Dictionary:
			_all_appearances["player"] = (stored as Dictionary).duplicate()
	# Load NPC appearances from GameState
	if gs and "npc_appearances" in gs:
		var npc_ap = gs.get("npc_appearances")
		if npc_ap is Dictionary:
			for k in npc_ap:
				_all_appearances[String(k)] = (npc_ap[k] as Dictionary).duplicate()
	# Seed NPC defaults from MainWorld.NPC_DATA if not yet customized
	var mw : Node = get_tree().current_scene
	if mw and "NPC_DATA" in mw:
		var npc_data = mw.get("NPC_DATA")
		if npc_data is Dictionary:
			for npc_id in npc_data:
				if not _all_appearances.has(npc_id):
					var d : Dictionary = npc_data[npc_id]
					_all_appearances[npc_id] = d.get("appearance", {}).duplicate()
	# Apply defaults for player
	if not _all_appearances.has("player"):
		_all_appearances["player"] = {}
	_character_id = "player"
	_appearance = _all_appearances["player"]
	_ensure_defaults(_appearance)

static func _ensure_defaults(ap: Dictionary) -> void:
	if not ap.has("shirt_color"):
		ap["shirt_color"] = Color(0.96, 0.45, 0.12)
	if not ap.has("pants_color"):
		ap["pants_color"] = Color(0.10, 0.15, 0.32)
	if not ap.has("hair"):
		ap["hair"] = "short"
	if not ap.has("beard"):
		ap["beard"] = "none"
	if not ap.has("cap"):
		ap["cap"] = false
	if not ap.has("ppe"):
		ap["ppe"] = "hi_vis"
	if not ap.has("hair_color"):
		ap["hair_color"] = Color(0.09, 0.07, 0.06)
	if not ap.has("skin_color"):
		ap["skin_color"] = Color(0.94, 0.78, 0.66)

func _set_appearance(key: String, value) -> void:
	_appearance[key] = value
	_all_appearances[_character_id] = _appearance
	_rebuild_preview_body()

func _switch_character(char_id: String) -> void:
	_all_appearances[_character_id] = _appearance
	_character_id = char_id
	if not _all_appearances.has(char_id):
		_all_appearances[char_id] = {}
	_appearance = _all_appearances[char_id]
	_ensure_defaults(_appearance)
	_rebuild_form()
	_rebuild_preview_body()

func _commit_to_gamestate() -> void:
	var gs : Node = get_node_or_null("/root/GameState")
	if gs == null:
		return
	_all_appearances[_character_id] = _appearance
	var color_keys : Array = ["shirt_color", "pants_color", "hair_color", "skin_color"]
	# Save player appearance
	var player_save : Dictionary = _all_appearances.get("player", {}).duplicate()
	for ck in color_keys:
		var c = player_save.get(ck)
		if c is Color:
			player_save[ck] = {"r": c.r, "g": c.g, "b": c.b}
	gs.set("player_appearance", player_save)
	# Save NPC appearances
	var npc_save : Dictionary = {}
	for k in _all_appearances:
		if k == "player":
			continue
		var ap : Dictionary = _all_appearances[k].duplicate()
		for ck in color_keys:
			var c = ap.get(ck)
			if c is Color:
				ap[ck] = {"r": c.r, "g": c.g, "b": c.b}
		npc_save[k] = ap
	gs.set("npc_appearances", npc_save)
	if gs.has_method("save_game"):
		gs.call("save_game")
	# Rebuild in-world bodies
	_rebuild_world_bodies()

# ── Preview body ────────────────────────────────────────────────────────────
func _rebuild_preview_body() -> void:
	if _preview_turntable == null:
		return
	if _preview_body and is_instance_valid(_preview_body):
		_preview_body.queue_free()
		_preview_body = null
	var script = load(HUMANOID_SCRIPT_PATH)
	if script == null:
		return
	var shirt : Color = _appearance.get("shirt_color", Color(0.96, 0.45, 0.12))
	# Humanoid.build takes a `shirt` Color + an `appearance` Dictionary it
	# already knows how to read (hair / beard / cap). We pass through the
	# colour keys it understands.
	var ap_for_humanoid : Dictionary = _appearance.duplicate()
	# Humanoid currently reads only hair/beard/cap from appearance; pants tint
	# would need a Humanoid extension. Pass it through so the future hook
	# lights up automatically.
	_preview_body = script.build(shirt, 0, ap_for_humanoid)
	_preview_body.position = Vector3(0.0, 0.92, 0.0)   # capsule-centre origin
	_preview_turntable.add_child(_preview_body)

func _process(delta: float) -> void:
	# Slow auto-spin only when the operator isn't actively dragging.
	if _preview_turntable and not _drag_active:
		_preview_turntable.rotation.y += delta * 0.35

# ── Input ────────────────────────────────────────────────────────────────────
func _on_preview_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_drag_active = mb.pressed
			if _drag_active:
				_drag_last_x = mb.position.x
	elif event is InputEventMouseMotion and _drag_active:
		var mm := event as InputEventMouseMotion
		var dx : float = mm.position.x - _drag_last_x
		_drag_last_x = mm.position.x
		if _preview_turntable:
			_preview_turntable.rotation.y -= dx * 0.012

func _rebuild_world_bodies() -> void:
	var humanoid_script = load(HUMANOID_SCRIPT_PATH)
	if humanoid_script == null:
		return
	var scene_root : Node = get_tree().current_scene
	if scene_root == null:
		return
	# Rebuild player body
	var player_node : Node = scene_root.get("player")
	if player_node:
		var old_body := player_node.find_child("PlayerBody", false, false)
		if old_body:
			old_body.get_parent().remove_child(old_body)
			old_body.queue_free()
		var ap : Dictionary = _all_appearances.get("player", {})
		var shirt : Color = Color(0.96, 0.45, 0.12)
		var sc = ap.get("shirt_color", shirt)
		if sc is Color: shirt = sc
		elif sc is Dictionary and sc.has("r"):
			shirt = Color(float(sc["r"]), float(sc["g"]), float(sc["b"]))
		var body : Node3D = humanoid_script.build(shirt, 0, ap)
		body.name = "PlayerBody"
		_set_render_layers_recursive(body, 1 << 1)
		player_node.add_child(body)
	# Rebuild NPC bodies
	for npc_id in _all_appearances:
		if npc_id == "player":
			continue
		var mw = scene_root
		if not "NPC_DATA" in mw:
			continue
		var npc_data = mw.get("NPC_DATA")
		if not npc_data is Dictionary or not npc_data.has(npc_id):
			continue
		var data : Dictionary = npc_data[npc_id]
		var npc_node : Node = scene_root.find_child(String(data.get("name", npc_id)), true, false)
		if npc_node == null:
			continue
		var old_body := npc_node.find_child("HumanoidBody", false, false)
		var variant : int = 0
		if old_body:
			old_body.get_parent().remove_child(old_body)
			old_body.queue_free()
		