extends RefCounted
class_name TitechShaftCut

## TITECH/TOMRA shaft-wrap CUT interaction — sibling to PelletizerKnifeReplace.
##
## CONTRACT
##   Player carries the WireCutter tool (tool_id == "scissors"; the "concrete
##   scissors" prop in WireCutter.gd) in the active inventory slot. They aim at
##   the placed NIR sorter body (a node with meta "placeable_id" in
##   {titech_sort, tomra_sort, nir_sorter}). That body carries a meta
##   "nir_sorter_ctrl" (a NirSorter instance, stamped by NirSorter.bind() during
##   LineFlow._attach_advanced_systems). Holding E for HOLD_DURATION_S removes
##   CUT_REMOVE_G of fibrous wrap; releasing early cancels.
##
##   Only valid when the sorter's current wrap_g > MIN_WRAP_FOR_CUT — there's no
##   reason to start the hold on a clean shaft, and the prompt should NOT show
##   up for sorters that don't have a fault.
##
## RESPONSIBILITIES (mirroring PelletizerKnifeReplace exactly so PlayerController
## can drive both with the same pattern):
##   - try_begin(player, nir_node) — wire-cutter held + nir target valid + wrap
##     above the cut threshold. Caches the controller for tick/complete.
##   - tick_hold(delta) — integrate progress while the SAME nir sorter stays
##     under the crosshair (the CALLER re-validates each tick and calls cancel()
##     if the ray drifts off).
##   - complete(nir_node) — call NirSorter.cut_wrap(CUT_REMOVE_G) and clear the
##     in-flight state.
##
## DESIGN NOTE — why static, not a node?
##   PlayerController owns the per-frame target+input state; the helper only
##   needs progress, validation, and the resolved cut call. Living as static
##   state mirrors PelletizerKnifeReplace and keeps the controller's hold-E
##   branch lean + unit-testable from a single entry point.

const HOLD_DURATION_S    : float = 1.5
const CUT_REMOVE_G       : float = 250.0
const MIN_WRAP_FOR_CUT   : float = 50.0
const WIRE_CUTTER_TOOL_ID : String = "scissors"
const NIR_PLACEABLE_IDS  : Array[String] = ["titech_sort", "tomra_sort", "nir_sorter"]

# ── State (singleton-style — one hold in flight at a time per player) ──────────
static var _progress      : float = 0.0
static var _active_nir    : Node3D   = null
static var _active_ctrl   : Object   = null   # NirSorter — cached on try_begin

## Begin a hold on `nir_node`. Returns true if the begin is allowed (wire-cutter
## active + nir target valid + wrap above MIN_WRAP_FOR_CUT). Does NOT tick — the
## caller drives tick_hold() each frame the player keeps E held on the same nir.
static func try_begin(player: Node3D, nir_node: Node3D) -> bool:
	if player == null or nir_node == null:
		return false
	if not is_instance_valid(nir_node):
		return false
	if not _is_valid_nir(nir_node):
		return false
	if not _player_holds_wire_cutter(player):
		return false
	var ctrl = _resolve_controller(nir_node)
	if ctrl == null:
		return false
	# Don't start the hold on a clean shaft — there's nothing to cut. wrap_g()
	# is the NirSorter accessor; the underlying TitechShaftWrap counts grams.
	if not ctrl.has_method("wrap_g"):
		return false
	if float(ctrl.call("wrap_g")) <= MIN_WRAP_FOR_CUT:
		return false
	_progress = 0.0
	_active_nir = nir_node
	_active_ctrl = ctrl
	return true

## Returns the live progress (0..1). When 1.0 the caller should call complete().
static func tick_hold(delta: float) -> float:
	if _active_nir == null or not is_instance_valid(_active_nir):
		_progress = 0.0
		return 0.0
	_progress = clampf(_progress + delta / HOLD_DURATION_S, 0.0, 1.0)
	return _progress

## Current hold progress without advancing it.
static func progress() -> float:
	return _progress

## True if a hold is currently in flight on `nir_node`.
static func is_active_on(nir_node: Node) -> bool:
	return _active_nir != null and _active_nir == nir_node

## True if any hold is in flight.
static func is_active() -> bool:
	return _active_nir != null and is_instance_valid(_active_nir)

## Abandon the hold (player released E early, or the ray drifted off).
static func cancel() -> void:
	_progress = 0.0
	_active_nir = null
	_active_ctrl = null

## Commit the cut. Returns true if wrap was actually removed. Always clears the
## in-flight state, even on a no-op path (no controller, freed node, etc.).
static func complete(nir_node: Node3D) -> bool:
	# Snapshot + clear up front so a recursive/early-return path can't leave
	# stale state behind.
	var node := nir_node
	var ctrl = _active_ctrl
	_progress = 0.0
	_active_nir = null
	_active_ctrl = null
	if node == null or not is_instance_valid(node):
		return false
	if not _is_valid_nir(node):
		return false
	if ctrl == null or not is_instance_valid(ctrl):
		ctrl = _resolve_controller(node)
		if ctrl == null:
			return false
	if not ctrl.has_method("cut_wrap"):
		push_warning("[ShaftCut] NIR controller has no cut_wrap()")
		return false
	var removed : float = float(ctrl.call("cut_wrap", CUT_REMOVE_G))
	return removed > 0.0

# ── Validation helpers ────────────────────────────────────────────────────────

static func _is_valid_nir(node: Node) -> bool:
	if not node.has_meta("placeable_id"):
		return false
	var pid := String(node.get_meta("placeable_id"))
	return NIR_PLACEABLE_IDS.has(pid)

static func _player_holds_wire_cutter(player: Node3D) -> bool:
	var inv : Node = null
	if player.is_inside_tree():
		inv = player.get_node_or_null("/root/Inventory")
	if inv == null:
		return false
	if not inv.has_method("active"):
		return false
	var t = inv.call("active")
	if t == null or not is_instance_valid(t):
		return false
	# WireCutter exposes a `tool_id` const ("scissors"); string-match for
	# resilience against script renames / scene-instance variants.
	if "tool_id" in t and String(t.get("tool_id")) == WIRE_CUTTER_TOOL_ID:
		return true
	# Fallback: group check (WireCutter._ready adds itself to "wire_cutter").
	if t.is_in_group("wire_cutter"):
		return true
	return false

## Pull the cached NirSorter controller off the sorter body (stamped by
## NirSorter.bind() during LineFlow._attach_advanced_systems). Returns null if
## the sorter hasn't been wired into a line yet (the LineFlow hasn't rebuilt
## since the placement).
static func _resolve_controller(nir_node: Node) -> Object:
	if not nir_node.has_meta("nir_sorter_ctrl"):
		return null
	var ctrl = nir_node.get_meta("nir_sorter_ctrl")
	if ctrl == null or not is_instance_valid(ctrl):
		return null
	return ctrl
