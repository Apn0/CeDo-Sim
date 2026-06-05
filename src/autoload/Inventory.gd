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

const NUM_SLOTS : int = 4

var slots       : Array = [null, null, null, null]   # Array[Node3D|null]
var active_idx  : int   = 0
var player_ref  : Node3D = null                       # set by PlayerController._ready

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
	var prev : Node3D = slots[active_idx]
	if prev != null and prev.has_method("on_holster"):
		prev.call("on_holster")
	active_idx = idx
	var now : Node3D = slots[active_idx]
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
	var t : Node3D = slots[idx]
	if t == null:
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
		var t : Node3D = slots[i]
		if t == null:
			continue
		t.visible = (i == active_idx)
		if t is CollisionObject3D:
			(t as CollisionObject3D).collision_layer = 0
			(t as CollisionObject3D).collision_mask  = 0

func _head() -> Node3D:
	if player_ref == null:
		return null
	return player_ref.get_node_or_null("Head") as Node3D
