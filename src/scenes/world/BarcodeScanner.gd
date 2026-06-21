extends StaticBody3D
class_name BarcodeScanner

## Pistol-grip 1D barcode scanner — read labels off bales / containers /
## machines / consumables. Same pickup-and-hold contract as WireCutter so it
## composes naturally with Inventory: walk up, E to pick up, swap to it via
## hotbar (1-4), point the camera at something with a child `Label` node, LMB
## to scan. The scan result floats over the HUD for ~3 seconds.
##
## Why "scannable" is a group + a child Label: the operator should be able to
## scan more than bales (raw material drums, finished granulate bins, machine
## ID plates), and the LineFlow / save layer might want to read the same info
## without piggy-backing on visual labels. So labels carry pure data
## (`label_info` metadata Dictionary) and the scanner just reads it.
##
## RIGHT-mouse while held = "peel" the label off whatever you scanned last,
## putting a detached LabelItem into your inventory. Used to re-label a
## stripped bale or move a tag between buffers.

const tool_id : String = "scanner"

const SCAN_RANGE     : float = 4.0     # max distance the laser reaches
const SCAN_COOLDOWN  : float = 0.25    # don't spam-scan on held LMB
const PICKUP_RANGE   : float = 1.6

var _held_by      : Node3D = null
var _player_near  : bool   = false
var _player_node  : Node   = null
var _last_scan_t  : float  = 0.0
var _last_scanned : Node   = null      # remember for RMB-peel

# =============================================================================
func _ready() -> void:
	add_to_group("barcode_scanner")
	_build_visual()
	_build_pickup_trigger()

## Yellow pistol-grip scanner: handle + body + LED + window.
func _build_visual() -> void:
	var yellow := StandardMaterial3D.new()
	yellow.albedo_color = Color(0.95, 0.78, 0.10)
	yellow.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12)
	dark.roughness = 0.8
	var window_m := StandardMaterial3D.new()
	window_m.albedo_color = Color(0.10, 0.10, 0.14)
	window_m.metallic = 0.4
	window_m.roughness = 0.10
	var led_m := StandardMaterial3D.new()
	led_m.albedo_color = Color(0.20, 1.00, 0.30)
	led_m.emission_enabled = true
	led_m.emission = Color(0.20, 1.00, 0.30, 1)
	led_m.emission_energy_multiplier = 1.6
	# Body (the bit you scan WITH — the -Z face is the window, matching Godot camera-forward)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.07, 0.10, 0.20)
	body.mesh = bm; body.material_override = yellow
	body.position = Vector3(0.0, 0.04, -0.05)
	add_child(body)
	# Scanner window (black panel on the front face of the body)
	var win := MeshInstance3D.new()
	var wm := BoxMesh.new(); wm.size = Vector3(0.05, 0.06, 0.005)
	win.mesh = wm; win.material_override = window_m
	win.position = Vector3(0.0, 0.04, -0.155)
	add_child(win)
	# Status LED on the top of the body
	var led := MeshInstance3D.new()
	var lm := SphereMesh.new(); lm.radius = 0.012; lm.height = 0.024
	led.mesh = lm; led.material_override = led_m
	led.position = Vector3(0.0, 0.10, 0.05)
	add_child(led)
	# Pistol grip below
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new(); gm.size = Vector3(0.05, 0.14, 0.06)
	grip.mesh = gm; grip.material_override = dark
	grip.position = Vector3(0.0, -0.06, 0.02)
	add_child(grip)
	# Trigger (small darker block on the inside of the grip)
	var trig := MeshInstance3D.new()
	var tm := BoxMesh.new(); tm.size = Vector3(0.025, 0.04, 0.03)
	trig.mesh = tm; trig.material_override = dark
	trig.position = Vector3(0.0, -0.02, -0.025)
	add_child(trig)
	# Bounding collision so it doesn't fall through the floor
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.10, 0.22, 0.24)
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

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		return
	# Only respond when WE are the active inventory slot — otherwise the player
	# holds e.g. scissors and pressing E should drop the scissors, not us.
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tool_use"):
		_scan_in_front()
		get_viewport().set_input_as_handled()
		return
	# RMB → peel the label off the LAST thing we scanned, into inventory.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			_peel_last_label()
			get_viewport().set_input_as_handled()
			return

func crosshair_prompt(_player: Node3D) -> String:
	return "Take barcode scanner" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	var inv := get_node_or_null("/root/Inventory")
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# tool ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it on the floor and prompt the player.
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
	# Held transform: local -Z is camera-forward, so the window now points away
	# from the operator and the pistol grip sits back toward the hand.
	transform = Transform3D(Basis(), Vector3(0.22, -0.18, -0.45))
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

# =============================================================================
# SCAN — raycast forward, look for a child "Label" node, show its data
# =============================================================================
func _scan_in_front() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scan_t < SCAN_COOLDOWN:
		return
	var cam : Camera3D = null
	if _held_by:
		cam = _held_by.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		return
	var from := cam.global_position
	var to   := from - cam.global_transform.basis.z * SCAN_RANGE
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [get_rid()]
	# Player capsule also excluded — we'd otherwise hit ourselves.
	if _held_by is PhysicsBody3D:
		q.exclude = [get_rid(), (_held_by as PhysicsBody3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_banner("[scan]  No label in sight")
		return
	var node : Node = hit.get("collider")
	# Climb to the nearest ancestor that owns a Label child.
	var labelled : Node = null
	var n : Node = node
	while n != null:
		if n.has_method("get_node_or_null") and n.get_node_or_null("Label"):
			labelled = n
			break
		n = n.get_parent()
	if labelled == null:
		_banner("[scan]  %s — no label" % node.name)
		return
	_last_scan_t  = now
	_last_scanned = labelled
	# Scan gate (#152): mark a scanned bale so the feed belt will accept it.
	if labelled.is_in_group("bale"):
		if labelled.has_meta("scanned") and labelled.get_meta("scanned"):
			_banner("[scan] ERROR: Bale already scanned!", true)
			return
		labelled.set_meta("scanned", true)
	var label := labelled.get_node_or_null("Label")
	var info : Dictionary = {}
	if label and label.has_meta("label_info"):
		info = label.get_meta("label_info") as Dictionary
	var txt := _format_label(labelled.name, info)
	if labelled.is_in_group("bale"):
		txt += "\n   ✓ SCANNED — cleared for the feed belt"
	_banner(txt)
	if labelled.is_in_group("bale"):
		_log_scan(labelled, info)   # #3 — record the row to the shift-leader scan log
	# Print a copy to console so you can grep the log later.
	print("[BarcodeScanner] " + txt)

func _format_label(host_name: String, info: Dictionary) -> String:
	if info.is_empty():
		return "[scan]  %s   (no data)" % host_name
	var lines := PackedStringArray()
	lines.append("[scan]  %s" % host_name)
	for k in info.keys():
		lines.append("   %s : %s" % [String(k), str(info[k])])
	return "\n".join(lines)

# =============================================================================
# SCAN LOG (#3) — every real scan becomes a row on the shift-leader's computer
# =============================================================================
## Build a structured row from the bale's label data and the shift clock, then
## broadcast it. ScanLog (autoload) records it; the office terminal displays it.
func _log_scan(bale: Node, info: Dictionary) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus == null or not bus.has_signal("bale_scanned"):
		return
	var clock := _shift_clock()
	var entry := {
		"batch":     String(info.get("batch", "—")),
		"item":      String(info.get("item", bale.name)),
		"origin":    String(info.get("origin", "—")),
		"weight_kg": int(info.get("weight_kg", 0)),
		"line":      "3C",                      # the LDPE film wash line these bales feed
		"by":        "Operator",                # the player scanned it (the operator on shift)
		"time":      (clock.call("get_time_string") if clock else "--:--:--"),
		"elapsed":   (clock.call("get_elapsed_seconds") if clock else 0.0),
	}
	bus.emit_signal("bale_scanned", entry)

func _shift_clock() -> Node:
	var scene := get_tree().current_scene
	return scene.find_child("ShiftClock", true, false) if scene else null

# =============================================================================
# PEEL — turn the last-scanned Label into a held LabelItem in inventory
# =============================================================================
func _peel_last_label() -> void:
	if _last_scanned == null or not is_instance_valid(_last_scanned):
		_banner("[peel]  Scan something first")
		return
	var label := _last_scanned.get_node_or_null("Label")
	if label == null:
		_banner("[peel]  Already peeled")
		return
	var info : Dictionary = {}
	if label.has_meta("label_info"):
		info = label.get_meta("label_info") as Dictionary
	# Tear the existing label off the host
	label.queue_free()
	# Drop a fresh LabelItem at the player's feet — the operator can pick it up
	# (E) to stash in inventory, then re-attach it elsewhere later.
	var item := LabelItem.new()
	item.label_info = info.duplicate()
	item.origin_host_name = _last_scanned.name
	var scene_root := get_tree().current_scene
	scene_root.add_child(item)
	var drop_pos := _held_by.global_transform * Vector3(0.0, -0.5, -0.8)
	item.global_position = drop_pos
	_banner("[peel]  Pulled label off %s — pick it up to stash" % _last_scanned.name)
	_last_scanned = null

# =============================================================================
# UI helpers
# =============================================================================
func _banner(text: String, is_error: bool = false) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", text, is_error)
		return
	# Fallback if EventBus doesn't yet expose the signal: print only.
	print(text)

func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
