extends StaticBody3D
class_name BatteryStation

## The walkie-battery point in the shift-leader's office (near the extruders).
##
## Three holders model the real bench:
##   • CHARGER  — exactly ONE slot. A pack left here tops up over ~4 h of shift
##                time. The single slot is the whole point: it's a shared resource.
##   • DRAWER   — the "ready" drawer of charged packs other operators left behind.
##   • SHELF    — empties waiting their turn in the charger.
##
## The intended loop (emergent from these rules, not scripted):
##   1. Your pack is low → take a fresh one from the DRAWER, swap it into your
##      walkie, and (if you're decent) drop your empty on the SHELF.
##   2. If the CHARGER finished a pack, lift the full one out → put it in the
##      DRAWER for the next person, then load a SHELF empty into the now-free
##      charger. Four hours later it's the drawer-pack someone else collects.
##
## All charge math runs in shift-seconds via Battery, so it only advances while
## the shift clock ticks. The node is fully driven by public methods so the logic
## is testable headless; the in-world model + proximity prompt are cosmetic.

## Battery is a global class, but the headless `--script` harness doesn't build the
## global class registry, so we preload the type. In-game it's the same class.
const BatteryT := preload("res://src/sim/Battery.gd")

signal station_changed   # emitted whenever holders change, so a HUD can refresh

# ── Holders ───────────────────────────────────────────────────────────────────
var charger : BatteryT = null           # the single charging slot (may be null)
var drawer  : Array = []                # charged-and-ready packs (Array[BatteryT])
var shelf   : Array = []                # empties awaiting a charger turn

# How many packs the office starts with (besides the one in the player's walkie).
const START_DRAWER_FULL : int = 1       # one ready pack waiting
const START_SHELF_EMPTY : int = 2       # two empties to seed the charger loop

var _player_near : bool = false

# =============================================================================
func _ready() -> void:
	add_to_group("battery_station")
	_seed_packs()
	_build_trigger()

## Seed the bench so the loop is live from shift one: a ready pack in the drawer,
## a couple of empties on the shelf, and one empty already charging.
func _seed_packs() -> void:
	for i in START_DRAWER_FULL:
		drawer.append(BatteryT.new(1.0, "pack_drawer_%d" % i))
	for i in START_SHELF_EMPTY:
		shelf.append(BatteryT.new(0.0, "pack_shelf_%d" % i))
	# Kick one empty off the shelf into the charger so it's already working.
	if not shelf.is_empty():
		charger = shelf.pop_back()

func _process(delta: float) -> void:
	# Advance the charger only while the shift is running.
	if charger == null:
		return
	var sc := _shift()
	if sc == null or not bool(sc.get("shift_active")):
		return
	if charger.top_up(delta):
		emit_signal("station_changed")    # just hit full — let the HUD ping

var _shift_clock : Node = null
func _shift() -> Node:
	if _shift_clock == null or not is_instance_valid(_shift_clock):
		var scene := get_tree().current_scene
		if scene:
			_shift_clock = scene.find_child("ShiftClock", true, false)
	return _shift_clock

# =============================================================================
# PUBLIC ACTIONS (the swap loop — also the headless-test surface)
# =============================================================================
## Swap the player's walkie pack for the best ready pack in the drawer. Returns
## true if a swap happened. The removed pack is handed back to the caller's choice
## via the returned dict so the UI can decide where it goes; by default we DON'T
## auto-shelve it (being thoughtful is a player choice, per the design).
func take_fresh_into_walkie() -> bool:
	if drawer.is_empty():
		return false
	# Best (fullest) ready pack.
	drawer.sort_custom(func(a, b): return a.charge < b.charge)
	var fresh : BatteryT = drawer.pop_back()
	var w := _walkie()
	if w == null:
		drawer.append(fresh)   # no walkie to swap into — put it back
		return false
	# Hand the old pack to the player's hands (held), not auto-filed.
	_held = w.swap_battery(fresh)
	emit_signal("station_changed")
	return true

## Put the pack the player is holding onto the SHELF (the considerate move:
## leaving your empty to be charged for the next person).
func shelve_held() -> bool:
	if _held == null:
		return false
	shelf.append(_held)
	_held = null
	emit_signal("station_changed")
	return true

## Put the held pack into the DRAWER (e.g. a full one you pulled from the charger).
func drawer_held() -> bool:
	if _held == null:
		return false
	drawer.append(_held)
	_held = null
	emit_signal("station_changed")
	return true

## Lift the pack out of the charger into the player's hands (to file it in the
## drawer). Returns false if the charger is empty.
func take_from_charger() -> bool:
	if charger == null or _held != null:
		return false
	_held = charger
	charger = null
	emit_signal("station_changed")
	return true

## Load the held pack into the (empty) charger.
func put_held_in_charger() -> bool:
	if _held == null or charger != null:
		return false
	charger = _held
	_held = null
	emit_signal("station_changed")
	return true

## Load the next SHELF empty straight into the charger (convenience for the loop).
func charge_next_shelf_empty() -> bool:
	if charger != null or shelf.is_empty():
		return false
	# Charge the emptiest first.
	shelf.sort_custom(func(a, b): return a.charge > b.charge)
	charger = shelf.pop_back()
	emit_signal("station_changed")
	return true

# Pack currently in the player's hands at the bench (null = empty-handed).
var _held : BatteryT = null
func held() -> BatteryT: return _held

# Optional direct reference (used by the headless test, where autoloads aren't
# active). In-game this stays null and we resolve the Walkie autoload from the root.
var walkie_ref : Node = null

func _walkie() -> Node:
	if walkie_ref != null and is_instance_valid(walkie_ref):
		return walkie_ref
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		return (ml as SceneTree).root.get_node_or_null("Walkie")
	return null

# ── Status for a future HUD / the test ────────────────────────────────────────
func charger_percent() -> int:    return charger.percent() if charger != null else -1
func drawer_count() -> int:       return drawer.size()
func shelf_count() -> int:        return shelf.size()
func ready_pack_count() -> int:   # packs anywhere that are charged & usable
	var n := drawer.size()
	if charger != null and charger.is_full(): n += 1
	return n

# =============================================================================
# PROXIMITY PROMPT (same pattern as Hmi.gd) — opens a bench UI later
# =============================================================================
func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "BatteryTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 2.4, 2.4)
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
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Battery bench — swap / charge")

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
