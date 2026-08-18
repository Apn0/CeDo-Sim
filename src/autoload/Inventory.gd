extends Node

## Tiny inventory for hand-held tools — scissors, barcode scanner, peeled
## label, charging plug, etc. Four slots. Press 1-4 to switch which slot is
## "in hand" (active); the active item is visible at the camera's hand
## position, the others are hidden but kept parented under the player's Head.
##
## ACTUAL WHY: before this autoload existed each tool (WireCutter only, at the
## time) hard-parented itself under the player's Head on pickup and reparented
## back to the world on E-drop — fine for one tool but the moment we needed a
## scanner AND scissors at the same time we had no way to swap between them.
## This makes the swap deterministic and gives the HUD toolbar a single source
## of truth.
##
## Tool contract (every tool that wants to live here):
##   - is a Node3D (or subclass) with `register_with_inventory(player: Node3D)`
##     called from its pickup branch (instead of hard-parenting itself).
##     Inventory does the parenting + show/hide.
##   - exposes `tool_id : String` (used by the HUD toolbar label).
##   - optional `on_holster()` / `on_draw()` callbacks if the tool needs to
##     pause/resume per-frame work when stashed.
##
## DROP semantics: Q drops the active item back onto the floor at the player's
## feet (chat-pickup-able with E). Per-tool pickup logic still owns the world
## ↔ inventory boundary; Inventory just manages the slots.

signal active_changed(new_idx: int)   # HUD listens; redraws the highlighted slot
signal slots_changed                  # HUD listens; redraws the contents

const NUM_SLOTS : int = 5   # #punch: operator asked for +1 (was 4)

var slots       : Array = [null, null, null, null, null]   # Array[Node3D|null] — NUM_SLOTS wide
var active_idx  : int   = 0
var player_ref  : Node3D = null                       # set by PlayerController._ready

# #223 audit: carried tools have real mass so a loaded belt slows the operator.
# Per-tool weight (kg) by tool_id; default 1 kg for anything unlisted.
const TOOL_MASS_KG : Dictionary = {
	"leaf_blower": 9.0, "water_hose": 4.0, "lpg_cylinder": 20.0,
	"wire_cutter": 0.6, "barcode_scanner": 0.5, "scissors": 0.3,
	"line_coupler": 0.5, "charging_plug": 1.5, "putty_knife": 0.4, "steel_brush": 0.5,
}
const DEFAULT_TOOL_MASS_KG : float = 1.0

## Total mass (kg) of everything currently in the four slots. PlayerController
## scales walk/sprint speed by this so a full belt genuinely trudges.
func total_carried_kg() -> float:
	var total : float = 0.0
	for t in slots:
		if t == null or not is_instance_valid(t):
			continue
		var tid : String = String(t.get("tool_id")) if "tool_id" in t else ""
		total += float(TOOL_MASS_KG.get(tid, DEFAULT_TOOL_MASS_KG))
	return total

# =============================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

# =============================================================================
# PUBLIC API
# =============================================================================

## Attach a tool to the first free slot. Returns true on success, false if
## inventory is full. Tool is reparented under the player's Head; if there's no
## active item, this tool becomes active. Other tools stay hidden.
func take(tool: Node3D) -> bool:
	if tool == null or player_ref == null:
		return false
	var head := _head()
	if head == null:
		return false
	# Find first free slot
	var slot := -1
	for i in NUM_SLOTS:
		if slots[i] == null:
			slot = i
			break
	if slot < 0:
		return false  # full
	# Re-parent under head, preserve world-position briefly (the tool's own
	# pickup code will then move it to its held transform — we don't override).
	if tool.get_parent():
		tool.get_parent().remove_child(tool)
	head.add_child(tool)
	slots[slot] = tool
	# Hide everything that isn't currently active, then re-show only active.
	_apply_visibility()
	slots_changed.emit()
	if slots[active_idx] == null:
		# Empty active slot — switch to the new tool so the player sees it.
		set_active(slot)
	return true

## First-spawn loadout (operator 2026-07-16: starter tools already in the hotbar).
## Instantiates the starter hand tools and runs each tool's own _pick_up()
## so the held pose / _held_by / take() bookkeeping is identical to a real E-grab.
## Idempotent: self-heals freed slot refs (this autoload outlives the tool NODES
## across a scene reload) and skips any tool_id already held, so calling it on
## every spawn re-arms without duplicating.
const STARTER_TOOL_SCRIPTS : Array = [
	"res://src/scenes/world/WireCutter.gd",     # scissors
	"res://src/scenes/world/BarcodeScanner.gd", # scanner
	"res://src/scenes/world/LineCouplerTool.gd",# line coupler / PLC wire tool
	"res://src/scenes/world/ShovelTool.gd",     # shovel
]

func give_starter_tools() -> void:
	if player_ref == null or not is_instance_valid(player_ref):
		return
	var scene_root : Node = player_ref.get_tree().current_scene
	if scene_root == null:
		return
	# 1) Self-heal freed refs so is_full()/take() see the real free count.
	for i in NUM_SLOTS:
		if slots[i] != null and not is_instance_valid(slots[i]):
			slots[i] = null
	# 2) Which starter tool_ids are already held (live instances only)?
	var have : Dictionary = {}
	for t in slots:
		if t != null and is_instance_valid(t) and "tool_id" in t:
			have[String(t.get("tool_id"))] = true
	for path in STARTER_TOOL_SCRIPTS:
		var scr = load(path)
		if scr == null:
			continue
		var tool_node : Node3D = scr.new()
		var tid : String = String(tool_node.get("tool_id")) if "tool_id" in tool_node else ""
		if (tid != "" and have.has(tid)) or is_full():
			tool_node.free()   # already held, or belt full — don't duplicate
			continue
		scene_root.add_child(tool_node)   # runs _ready() (builds the tool)
		if tool_node.has_method("_pick_up"):
			tool_node.call("_pick_up", player_ref)
		else:
			take(tool_node)
	slots_changed.emit()

## True when every slot is occupied — no room to take another tool. Pickup paths
## MUST check this BEFORE grabbing an item: take() returns false when full but a
## caller that ignores the return and force-parents the item anyway strands it
## (parented under Head, in no slot → never active → can't be dropped).
func is_full() -> bool:
	for i in NUM_SLOTS:
		if slots[i] == null:
			return false
	return true

## Active tool node (or null).
func active() -> Node3D:
	return slots[active_idx]

## Switch which slot is in-hand. Hides the previously-active tool, shows the
## new one. Out-of-range or empty slots are allowed — the active hand becomes
## empty in that case (which is fine: think of it as "putting the tool away").
func set_active(idx: int) -> void:
	if idx < 0 or idx >= NUM_SLOTS:
		return
	if idx == active_idx:
		return
	# UNTYPED reads — slots[] can hold a FREED node (same crash class as
	# slot_label; a typed Node3D assignment throws before is_instance_valid can
	# guard it). Validate + self-heal the stale slot before touching it.
	var prev = slots[active_idx]
	if prev != null and not is_instance_valid(prev):
		slots[active_idx] = null
		prev = null
	if prev != null and prev.has_method("on_holster"):
		prev.call("on_holster")
	active_idx = idx
	var now = slots[active_idx]
	if now != null and not is_instance_valid(now):
		slots[active_idx] = null
		now = null
	if now != null and now.has_method("on_draw"):
		now.call("on_draw")
	_apply_visibility()
	active_changed.emit(active_idx)

## Drop the ACTIVE tool back into the world at the player's feet. Caller's job
## is the actual world reparent + collision re-enable (the tool's `_drop()`).
## We just clear the slot and ping listeners. Returns the tool that was
## dropped, or null if active slot was empty.
func drop_active() -> Node3D:
	var t : Node3D = slots[active_idx]
	if t == null:
		return null
	slots[active_idx] = null
	_apply_visibility()
	slots_changed.emit()
	return t

## Remove `tool` from whichever slot it occupies. Used by a tool's own _drop()
## when it returns to the world via its existing key handler (E for WireCutter).
func remove(tool: Node3D) -> void:
	for i in NUM_SLOTS:
		if slots[i] == tool:
			slots[i] = null
			_apply_visibility()
			slots_changed.emit()
			return

## Is the given tool currently active (in-hand and visible)?
func is_active(tool: Node3D) -> bool:
	return tool != null and slots[active_idx] == tool

## Used by HUD/save code.
func slot_label(idx: int) -> String:
	if idx < 0 or idx >= NUM_SLOTS:
		return ""
	# UNTYPED read: slots[idx] can hold a FREED node (a tool freed on scene
	# teardown / gauntlet start without being removed from the slot). Assigning a
	# freed instance to a typed `Node3D` var throws "invalid previously freed
	# instance" BEFORE is_instance_valid can guard it (crash on extruder-gauntlet
	# start, HUD.gd:1362). Read untyped, validate, and self-heal the stale slot.
	var t = slots[idx]
	if t == null or not is_instance_valid(t):
		slots[idx] = null
		return "—"
	# Prefer the tool's `tool_id` (e.g. "scissors", "scanner"); fall back to node name.
	if "tool_id" in t:
		return String(t.get("tool_id"))
	return t.name

# =============================================================================
# INTERNAL
# =============================================================================

## Show only the active tool; hide the rest. Collision is FORCED OFF for every
## held tool — active or not.
##
## THE BUG THIS FIXES (operator: "holding a tool and interacting flings me 50-
## 100 m like a hard wind"): the old code set the active tool's collision_layer
## /mask = 1 while the tool is parented under the player's Head, i.e. occupying
## the exact same space as the player capsule. Two overlapping physics bodies →
## Godot's depenetration solver violently ejects the (movable) player capsule
## away from the (newly-solid) tool. It fired on every take()/set_active()/
## remove(), which is why it felt random. Held tools ride with the player and
## must NEVER collide; the world-collision boundary is owned by each tool's own
## _drop() (which sets layer/mask = 1 only once it's back on the floor).
func _apply_visibility() -> void:
	for i in NUM_SLOTS:
		# UNTYPED read — a slot may hold a freed node (self-heal it rather than
		# crash on the typed assignment, same as slot_label / set_active).
		var t = slots[i]
		if t == null or not is_instance_valid(t):
			slots[i] = null
			continue
		t.visible = (i == active_idx)
		if t is CollisionObject3D:
			(t as CollisionObject3D).collision_layer = 0
			(t as CollisionObject3D).collision_mask  = 0

func _head() -> Node3D:
	if player_ref == null:
		return null
	return player_ref.get_node_or_null("Head") as Node3D
