extends StaticBody3D
class_name VacuumPotInteract
## P3 stage B (2026-09-24) — the crosshair body around a vacuum pot's dome
## (PlaceableCatalog builds one per pot as VacPot_<name>/PotService). It turns
## the player's E and hold-E into VacuumPotService calls:
##   lid ON, pot full   : hold E — pull the lid off (sticks: N s)
##   lid OFF, block in  : E with the plamuurmes — push it into the aimed cell;
##                        E again — pull it out; alternate until the planes clear
##   block free         : E — take the melt block out (into the hotbar)
##   block taken        : E — put the lid back on (the model gets vacuum_restored)
## Which cell the player pushes comes from where the crosshair ray hits this
## body: upper part = top plane, lower = bottom, else left/right by side; the
## cell by the quadrant of the hit point. Without a camera (tests) the next
## uncleared cell in his order is used.

# The service by PATH, not class_name: a fresh class_name is unknown to a
# standalone headless run until the editor (or the harness import step)
# rebuilds the global class cache — measured 2026-09-24 (this suite idled).
const VPS := preload("res://src/scenes/interactions/VacuumPotService.gd")
const PLAMUURMES_TOOL_ID : String = "tool_plamuurmes"
const _PROMPT_EVERY_S : float = 0.2

var _brain : Node = null
var _prompt_t : float = 0.0
var _last_prompt : String = ""

func _ready() -> void:
	add_to_group("vacuum_pot_service")

func pot_root() -> Node:
	return get_parent()

func _find_brain() -> Node:
	if _brain != null and is_instance_valid(_brain):
		return _brain
	# up to the catalog body, then its SimBrain child (group extruder_machine)
	var n : Node = get_parent()
	var body : Node = null
	while n != null:
		if n.has_meta("placeable_id"):
			body = n
			break
		n = n.get_parent()
	if body == null:
		return null
	for c in body.get_children():
		if c.is_in_group("extruder_machine"):
			_brain = c
			return c
	return null

func model():
	var b := _find_brain()
	return b.get("model") if b != null else null

func _has_plamuurmes(player: Node) -> bool:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or player == null:
		return false
	var t = inv.call("active")
	if t == null or not is_instance_valid(t):
		return false
	return "tool_id" in t and String(t.get("tool_id")) == PLAMUURMES_TOOL_ID

## ── prompts ──────────────────────────────────────────────────────────────────
func crosshair_prompt(player: Node3D) -> String:
	var m = model()
	var root := pot_root()
	if m == null or root == null:
		return ""
	var st := VPS.state(root)
	var nm := VPS.pot_name(root)
	if not bool(st["lid_off"]):
		if VPS.can_pull_lid(m, root):
			var need : float = VPS.lid_pull_required_s(m)
			if bool(st["pulling"]):
				return "Pulling the %s pot's lid… %.0f %%" % [nm, 100.0 * float(st["pull"])]
			return "Hold E: pull the %s pot's lid off (it sticks — %.0f s)" % [nm, need]
		return "Vacuum pot %s: %.1f kg" % [nm, VPS.pot_fill_kg(m, root)]
	if VPS.block_free(root):
		return "E: take the melt block out (%.1f kg)" % float(st["kg"])
	if st["block"] != null:
		if bool(st["tool_in"]):
			return "E: pull the plamuurmes out"
		if not _has_plamuurmes(player):
			return "Needs the plamuurmes (putty knife) in hand"
		var pp := VPS.plane_progress(root)
		return "E: push the plamuurmes — top %d%%  bottom %d%%  left %d%%  right %d%%" % [
			int(round(100.0 * float(pp["top"]))), int(round(100.0 * float(pp["bottom"]))),
			int(round(100.0 * float(pp["left"]))), int(round(100.0 * float(pp["right"])))]
	if VPS.can_relid(root):
		return "E: put the %s pot's lid back on" % nm
	return ""

func _show(_player: Node, text: String) -> void:
	if text == _last_prompt:
		return
	_last_prompt = text
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

## ── E ────────────────────────────────────────────────────────────────────────
func crosshair_interact(player: Node3D) -> void:
	var m = model()
	var root := pot_root()
	if m == null or root == null:
		return
	var st := VPS.state(root)
	if not bool(st["lid_off"]):
		return                                   # the lid is a HOLD, not a press
	if VPS.block_free(root):
		var block : Node = VPS.take_block(root, _find_brain())
		if block != null and player != null and block.has_method("pick_up"):
			block.call("pick_up", player)
		_show(player, crosshair_prompt(player))
		return
	if st["block"] != null:
		if bool(st["tool_in"]):
			VPS.pull_out(root)
		elif _has_plamuurmes(player):
			var aim := _aim(player)
			var res := VPS.push(m, root, String(aim[0]), int(aim[1]))
			if bool(res["ok"]):
				print("[VacuumPot] %s pot: plamuurmes into %s/%d → %.0f %% (%s)" % [
					VPS.pot_name(root), aim[0], int(aim[1]), 100.0 * float(res["clearance"]),
					"FREE" if bool(res["released"]) else "still stuck"])
		_show(player, crosshair_prompt(player))
		return
	if VPS.can_relid(root):
		VPS.relid(root, _find_brain())
		print("[VacuumPot] %s pot: lid back on — vacuum restore requested" % VPS.pot_name(root))
		_show(player, crosshair_prompt(player))

## Which plane / cell the player is pushing into: from the crosshair ray's hit
## on this body; the next uncleared cell in his order when there is no camera.
func _aim(player: Node) -> Array:
	var root := pot_root()
	var cam : Camera3D = player.get("camera_3d") if player != null and "camera_3d" in player else null
	if cam != null and is_inside_tree():
		var from : Vector3 = cam.global_position
		var to : Vector3 = from - cam.global_transform.basis.z * 4.0
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.collide_with_areas = false
		q.collide_with_bodies = true
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty() and hit.get("collider") == self:
			# Rulings §20: the opening is the +X face; the operator looks in
			# along -X. Upper part of the opening = the top plane, lower = the
			# bottom plane, else the wall on his LEFT (+Z when facing -X) or
			# RIGHT (-Z); the cell by the quadrant of the hit point.
			var lp : Vector3 = to_local(hit["position"])
			var box : BoxShape3D = null
			for c in get_children():
				if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
					box = (c as CollisionShape3D).shape
			var h : float = box.size.y if box != null else 0.2
			var plane := "left"
			if lp.y > h * 0.25:
				plane = "top"
			elif lp.y < -h * 0.25:
				plane = "bottom"
			elif lp.z < 0.0:
				plane = "right"
			var cell : int = (0 if lp.z >= 0.0 else 1) + (0 if lp.y >= 0.0 else 2)
			return [plane, cell]
	return VPS.next_cell(root)

## ── hold E (PlayerController._update_generic_hold) ──────────────────────────
func crosshair_hold_tick(delta: float, player: Node3D) -> float:
	var m = model()
	var root := pot_root()
	if m == null or root == null:
		return 0.0
	if not VPS.can_pull_lid(m, root):
		return 0.0
	var p : float = VPS.tick_lid_pull(m, root, delta)
	_prompt_t += delta
	if p >= 1.0:
		print("[VacuumPot] %s pot: lid pulled off after %.1f s of pulling" % [VPS.pot_name(root), VPS.lid_pull_required_s(m)])
		_show(player, crosshair_prompt(player))
	elif _prompt_t >= _PROMPT_EVERY_S:
		_prompt_t = 0.0
		_show(player, crosshair_prompt(player))
	return p

func crosshair_hold_cancel() -> void:
	var root := pot_root()
	if root != null:
		VPS.cancel_lid_pull(root)
	_prompt_t = 0.0
	_last_prompt = ""
