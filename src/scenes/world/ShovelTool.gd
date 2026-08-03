extends StaticBody3D
class_name ShovelTool

## A holdable SHOVEL for housekeeping the floor piles that build up under chutes
## (#154). Real flow: a chute reject heaps up on the floor → the operator parks a
## container nearby, picks up the shovel (E), walks to the heap, and LEFT-CLICKS
## to scoop it a shovelful at a time into the container (or just clears it if no
## bin is in reach). Same pickup/hold/drop UX as the WireCutter.

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "shovel"

const PICKUP_RANGE   : float = 1.6
const SCOOP_RANGE    : float = 2.2     # how close to the heap you must stand
const DEPOSIT_RANGE  : float = 3.0     # a bin this close catches the scoop
const SCOOP_KG       : float = 6.0     # mass lifted per scoop (a real shovelful of dirt ~5-8 kg, was an unrealistic 25)
const SCOOP_COOLDOWN : float = 0.4
const REFUSE_BANNER_COOLDOWN : float = 2.0   # held-LMB retries mustn't flicker the banner

var _held_by   : Node3D = null
var _last_scoop: float  = 0.0
var _last_refuse_banner : float = -REFUSE_BANNER_COOLDOWN
var _player_near : bool = false
var _player_node : Node = null

# =============================================================================
func _ready() -> void:
	add_to_group("shovel_tool")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.40, 0.22); wood.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78); steel.metallic = 0.8; steel.roughness = 0.3
	# Shaft
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new(); sm.top_radius = 0.025; sm.bottom_radius = 0.025
	sm.height = 0.95; sm.radial_segments = 10
	shaft.mesh = sm; shaft.material_override = wood
	shaft.position = Vector3(0, 0, 0.1)
	shaft.rotation.x = deg_to_rad(90.0)
	add_child(shaft)
	# Blade (a slightly dished box at the front)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.26, 0.04, 0.30)
	blade.mesh = bm; blade.material_override = steel
	blade.position = Vector3(0, 0, -0.5)
	add_child(blade)
	# Base collision so it rests on the floor.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.28, 0.1, 1.1)
	col.shape = bx
	add_child(col)

func _build_pickup_trigger() -> void:
	InteractionTriggers.make_pickup_trigger(
		self, PICKUP_RANGE, _on_body_entered, _on_body_exited)

# =============================================================================
# PICKUP / DROP (E)
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
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

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
		scoop_once()
		get_viewport().set_input_as_handled()
		return

func crosshair_prompt(_player: Node3D) -> String:
	return "Take shovel" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# tool ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it on the floor and prompt the player.
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
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
	transform = Transform3D(Basis(), Vector3(0.24, -0.20, -0.45))
	collision_layer = 0
	collision_mask  = 0
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

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
# USE — scoop one shovelful from the nearest heap into a nearby container
# =============================================================================
## Lift up to SCOOP_KG from the nearest floor pile in reach and tip it into the
## nearest waste container in reach (or discard it if none). Returns kg moved.
## Public + side-effect-only so a headless test can call it directly.
func scoop_once() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scoop < SCOOP_COOLDOWN:
		return 0.0
	var pile := _nearest_in_group("floor_pile", SCOOP_RANGE, true)
	if pile == null:
		_refuse_banner("Shovel: no pile within reach")
		return 0.0
	# CONSERVATION (operator 2026-07-16): a shovelful can't vanish into nothing —
	# it has to go SOMEWHERE. Require a container in reach BEFORE lifting anything
	# off the pile; with no bin, the scoop is refused and the material stays on the
	# pile (previously the mass was removed and silently deleted = mass→nothing).
	var bin := _nearest_in_group("waste_container", DEPOSIT_RANGE, false)
	if bin == null or not bin.has_method("add"):
		_refuse_banner("Shovel: need a waste container nearby — the scoop must go somewhere")
		return 0.0
	# A FULL bin can't accept the scoop — lifting anyway would overflow into the
	# void (mass deleted). Refuse the scoop so the pile keeps its material
	# (bughunt 2026-07-17: bin.add() caps at capacity and drops the remainder).
	if bin.has_method("is_full") and bool(bin.call("is_full")):
		_refuse_banner("Shovel: container is full — empty it first")
		return 0.0
	var got : float = pile.call("scoop", SCOOP_KG)
	if got <= 0.0:
		return 0.0
	_last_scoop = now
	# Mass moved from the pile INTO the bin — conserved, not created/destroyed.
	bin.call("add", got, 200.0, -1)
	return got

## Surface a scoop refusal REASON on the HUD scanner banner (qol: every refusal
## used to be a silent "LMB does nothing"). Throttled — a held LMB retries every
## SCOOP_COOLDOWN and the reason rarely changes within a couple of seconds.
func _refuse_banner(reason: String) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_refuse_banner < REFUSE_BANNER_COOLDOWN:
		return
	_last_refuse_banner = now
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", reason, true)

## Nearest node of `group` within `range_m`. When `need_mass`, only piles that
## actually hold material qualify (skip empty zones).
func _nearest_in_group(group: String, range_m: float, need_mass: bool) -> Node:
	var origin := global_position
	var best : Node = null
	var best_d := range_m
	for n in get_tree().get_nodes_in_group(group):
		var nn := n as Node3D
		if nn == null:
			continue
		if need_mass and float(nn.get("mass_kg")) <= 0.0:
			continue
		var d := nn.global_position.distance_to(origin)
		if d < best_d:
			best_d = d
			best = n
	return best
