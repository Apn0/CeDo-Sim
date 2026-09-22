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
## from the catalog entry — one of the 12 documented panels; the generic
## see-all fallback died with the retired `hmi_panel` / `hmi_wall` props, so an
## unrecognised id now leaves the panel INERT rather than granting plant-wide
## control). On interact, we look up the scope in HmiScopes.gd and pass
## it to HmiOverlay.open_for(scope, label) — the overlay then filters its
## SECTIONS / STAGES / MACHINES list / HANDBEDIENING rows / START-STOP gates by
## that scope, so this physical panel only ever shows + controls its assigned
## machines.
##
## Built by PlaceableCatalog.build_node() when category == "Control"; that
## function attaches this script to the body and lets _ready() do the rest.

const _OVERLAY_PATH := "res://src/scenes/hud/HmiOverlay.tscn"
const _SCOPES := preload("res://src/build/HmiScopes.gd")

# Path to the non-touchscreen relay panel for hmi_shredder2_l3ab (panel_type
# "relay"). Loaded lazily via load() rather than preload() so the relay class
# is optional — if the file is missing we still boot, the HMI just falls back
# to the touchscreen overlay.
const _RELAY_PANEL_PATH := "res://src/scenes/hud/panels/ShredderRelayPanel.gd"

# WebView overlay for scopes with a "web_screen" (task #2). load()ed lazily —
# if the file is missing the HMI silently falls back to the touchscreen.
const _WEB_OVERLAY_PATH := "res://src/scenes/hud/HmiWebOverlay.gd"

# One overlay instance is shared between every HMI in the world — opens for
# whichever panel the player most recently interacted with. The overlay is
# re-scoped on every open_for(), so opening HMI-A then HMI-B never leaks A's
# selection or machine list into B.
static var _overlay : CanvasLayer = null

# Separate static slot for the relay-cabinet panel (panel_type == "relay").
# Wrapped in a CanvasLayer so the Control floats over the world the same way
# the touchscreen overlay does. Re-used across every relay HMI.
static var _relay_layer : CanvasLayer = null
static var _relay_panel : Control = null

# Shared WebView overlay (task #2) — same one-instance pattern as _overlay.
static var _web_overlay : CanvasLayer = null

var _player_near : bool = false
var _label       : String = "HMI"
var _hmi_id      : String = ""
# False when this panel's hmi_id has no scope in HmiScopes.SCOPES. Such a panel
# renders but cannot be opened — see the class doc.
var _scoped      : bool = false

func _ready() -> void:
	add_to_group("hmi")
	# Resolve which of the 12 documented scopes this physical panel owns.
	_hmi_id = _SCOPES.resolve_hmi_id(self)
	if not _SCOPES.has_scope(_hmi_id):
		# No fallback by design: a see-all default would hand the player control
		# of the whole plant from a panel we cannot identify.
		push_warning("[Hmi] unknown hmi_id '%s' — panel left inert (no scope in HmiScopes.SCOPES)" % _hmi_id)
		return
	_scoped = true
	var scope := _SCOPES.get_scope(_hmi_id)
	_label = String(scope.get("label", "HMI"))
	_build_trigger()

## The scope's human title ("Shredder lijn 1"); "HMI" for an inert panel.
## Read by MapOverlay for its wayfinding label (Q5, 2026-09-23).
func scope_label() -> String:
	return _label

func _build_trigger() -> void:
	# Proximity zone around the HMI head — the player gets a prompt when in
	# range and can press the interact key to open the panel.
	var area := Area3D.new()
	area.name = "HmiTrigger"
	area.collision_mask = 1
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(4.0, 3.0, 4.0)
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
	return "Open %s" % _label if _scoped else ""

func crosshair_interact(_player: Node3D) -> void:
	if _scoped:
		_open_overlay()

## Lazy-loads the shared overlay on first use, then opens it scoped to THIS
## panel. Re-opening on a different HMI always re-applies its scope, so the
## list/sections never carry over from the previous panel.
##
## Branches on scope.panel_type (#207h) + scope.web_screen (task #2):
##   - "relay"           → load ShredderRelayPanel.gd (non-touchscreen cabinet)
##   - "web_screen" set  → HmiWebOverlay (Claude-Design .dc.html in a WebView);
##                         falls back to the touchscreen when the WebView
##                         addon can't run here (headless / class missing)
##   - otherwise         → load HmiOverlay.tscn (touchscreen — default)
func _open_overlay() -> void:
	var scope := _SCOPES.get_scope(_hmi_id)
	if scope.is_empty():
		push_warning("[Hmi] refusing to open '%s' — no scope (see HmiScopes.SCOPES)" % _hmi_id)
		return
	var panel_type := String(scope.get("panel_type", "touchscreen"))
	if panel_type == "relay":
		_open_relay_panel(scope)
		return
	if String(scope.get("web_screen", "")) != "" and _open_web_overlay(scope):
		return
	_open_touchscreen_overlay(scope)

## WebView path — the Claude-Design HMI exports rendered live (task #2).
## Returns false when the web overlay can't open so the caller can fall back
## to the GDScript touchscreen (same screen content, older look).
func _open_web_overlay(scope: Dictionary) -> bool:
	var overlay_script := load(_WEB_OVERLAY_PATH)
	if overlay_script == null:
		return false
	if not overlay_script.call("webview_available"):
		return false
	if _web_overlay == null or not is_instance_valid(_web_overlay):
		_web_overlay = overlay_script.new() as CanvasLayer
		if _web_overlay == null:
			return false
		get_tree().root.add_child(_web_overlay)
	if not _web_overlay.has_method("open_for"):
		return false
	_web_overlay.call("open_for", _label, scope)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	return true

## Touchscreen path — the original HmiOverlay.tscn behaviour.
func _open_touchscreen_overlay(scope: Dictionary) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		var scene := load(_OVERLAY_PATH) as PackedScene
		if scene == null:
			push_error("[Hmi] %s missing" % _OVERLAY_PATH)
			return
		_overlay = scene.instantiate() as CanvasLayer
		get_tree().root.add_child(_overlay)
	if _overlay.has_method("open_for"):
		# Pass BOTH the scope and the label so the overlay can filter its
		# screens. The overlay tolerates a missing scope arg (back-compat).
		_overlay.open_for(_label, scope)
	else:
		_overlay.visible = true
	# Free the mouse so the player can click the overlay buttons.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Relay-cabinet path — ShredderRelayPanel.gd is a Control, so wrap it in a
## CanvasLayer so it floats over the world the same way the touchscreen does.
## The panel's `request_close` signal hides the layer and restores the mouse.
func _open_relay_panel(_scope: Dictionary) -> void:
	if _relay_panel == null or not is_instance_valid(_relay_panel):
		var script := load(_RELAY_PANEL_PATH)
		if script == null:
			push_warning("[Hmi] relay panel script missing at %s — falling back to touchscreen" % _RELAY_PANEL_PATH)
			_open_touchscreen_overlay(_scope)
			return
		_relay_layer = CanvasLayer.new()
		_relay_layer.name = "HmiRelayLayer"
		_relay_layer.layer = 50
		get_tree().root.add_child(_relay_layer)
		_relay_panel = script.new()
		_relay_panel.name = "ShredderRelayPanel"
		# Stretch to viewport so the cabinet face centres itself.
		if _relay_panel is Control:
			(_relay_panel as Control).set_anchors_preset(Control.PRESET_FULL_RECT)
		_relay_layer.add_child(_relay_panel)
		# Single shared close handler — hides the layer + restores mouse capture.
		if _relay_panel.has_signal("request_close") and not _relay_panel.is_connected("request_close", Callable(self, "_on_relay_close")):
			_relay_panel.connect("request_close", Callable(self, "_on_relay_close"))
	# Tag this open with the panel's shredder_id so a debug overlay can tell
	# which physical cabinet it belongs to (the panel itself doesn't need the
	# full scope dict — it's a pure view widget).
	if "shredder_id" in _relay_panel:
		_relay_panel.set("shredder_id", _hmi_id)
	# Locate the shredder_2 model so the panel reflects real run state and
	# routes start/stop back to the machine. Mirrors how _open_touchscreen_overlay
	# resolves its scope-target via the "shredder" group + scope token match.
	_bind_relay_panel_to_shredder(_scope)
	_relay_layer.visible = true
	_relay_panel.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Find the shredder controller this relay panel is scoped to and wire its
## run state / start / stop into the panel. Tolerates a missing controller —
## a placed cabinet without a backing model just stays as a static view.
func _bind_relay_panel_to_shredder(scope: Dictionary) -> void:
	if _relay_panel == null or not is_instance_valid(_relay_panel):
		return
	var tokens : Array = scope.get("tokens", [])
	if tokens.is_empty():
		# Fall back to the canonical token for the shredder_2 panel.
		tokens = ["shredder_2"]
	var shredder : Node = _find_scoped_shredder(tokens)
	if shredder == null:
		# push_warning("[Hmi] No shredder controller found for scope %s — relay panel stays static. TODO: wire once shredder controller exists." % _hmi_id)
		return
	# Reflect the model's current run state on the panel face (best-effort).
	if shredder.has_method("is_running") and _relay_panel.has_method("set_running"):
		_relay_panel.call("set_running", bool(shredder.call("is_running")))
	# Connect: shredder.running → panel.set_running (state lamp follows model).
	if shredder.has_signal("running") and not shredder.is_connected("running", Callable(_relay_panel, "set_running")):
		shredder.connect("running", Callable(_relay_panel, "set_running"))
	# Connect: panel.start_pressed → shredder.start (operator wants run).
	if shredder.has_method("start") and not _relay_panel.is_connected("start_pressed", Callable(shredder, "start")):
		_relay_panel.connect("start_pressed", Callable(shredder, "start"))
	# Connect: panel.stop_pressed → shredder.emergency_stop (mushroom = e-stop).
	if shredder.has_method("emergency_stop") and not _relay_panel.is_connected("stop_pressed", Callable(shredder, "emergency_stop")):
		_relay_panel.connect("stop_pressed", Callable(shredder, "emergency_stop"))

## Walk the "shredder" group and pick the first node whose placeable_id (or
## node name) contains any of the scope tokens. Returns null if none match.
func _find_scoped_shredder(tokens: Array) -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	for s in tree.get_nodes_in_group("shredder"):
		if s == null or not is_instance_valid(s):
			continue
		var pid : String = ""
		if s.has_meta("placeable_id"):
			pid = String(s.get_meta("placeable_id"))
		var nname : String = String(s.name)
		for t in tokens:
			var tok := String(t)
			if tok.is_empty():
				continue
			if pid.find(tok) >= 0 or nname.find(tok) >= 0:
				return s
	return null

func _on_relay_close() -> void:
	if _relay_layer != null and is_instance_valid(_relay_layer):
		_relay_layer.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
